#<ACTION> file=>'kernel/ponmon.pm',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
package kernel::ponmon;
use strict;
use Debug;
use Db;
use nod::tasks;

use threads;
use threads::shared;
use Net::Ping;
use Time::localtime;

our @ISA = qw{kernel};

$cfg::_tbl_name_template = '%s_%02d';

$SIG{INT} = sub { die "\nCaught a sigint $!" };
$SIG{TERM} = sub { die "\nCaught a sigterm $!" };

sub CLONE()
{
    no warnings;
    Db->new(
        host    => $cfg::Db_server,
        user    => $cfg::Db_user,
        pass    => $cfg::Db_pw,
        db      => $cfg::Db_name,
        timeout => $cfg::Db_connect_timeout,
        tries   => 3, # попыток с интервалом в секунду соединиться
        global  => 1, # создать глобальный объект Db, чтобы можно было вызывать абстрактно: Db->sql()
        pool    => $cfg::Db_pool || [],
    ) or debug 'error','Can`t create new Db connection';
}

my $M = {};
$M->{step} = 0;
#share %M;
my %loaded_modules = ();
my %onu_list = ();
my $period = time();
my $running_threads = ( int($cfg::k_ponmon_max_threads) || 10);
my $history_period = int($cfg::k_ponmon_max_history) || 60;

sub start
{
    my(undef, $single, $config) = @_;

    nod::tasks->new(
        task         => sub{ main($_[0], $single, $config) },
        period       => ( int($cfg::k_ponmon_period)*60 || 600),
        first_period => $single? 0 : ( int($cfg::k_ponmon_period)*60 || 600),
    );
}

sub main
{
    my($task, $single, $config) = @_;
    my @threads = ();
    my $db = Db->sql(
        "SELECT o.*, d.name as tname, d.document, d.tags FROM `pon_olt` o ".
        "LEFT JOIN documents d ON (d.id = o.`mng_tmpl`) WHERE o.`enable` = 1"
    );
    my $rows = $db->rows || 0;
    if (!$rows) {
        debug "===> ERROR: No OLT in DB!!! Retrying after 60 seconds.";
        sleep 60;
        return 0;
    }

    $running_threads = $rows if $running_threads > $rows;

    my $np = Net::Ping->new();
    while( my %p = $db->line )
    {
        if ($np->ping($p{ip}))
        {
            my threads $t = threads->create(\&init_pon, \%p);
            push @threads, $t;
            $t->detach();
        }
        else
        {
            &olt_is_down(\%p);
        }

        while (wait_ps(\@threads, $running_threads)) { sleep 1; }
    }

    while (wait_ps(\@threads, 0)) {
        #debug  "Wait finish\n";
    }

    &_bind_fdb();
    &_clean_history() if $history_period;
    $M->{step}++;
    debug "_______$M->{step}";
}

sub wait_ps
{
    my($threads, $max_threads) = @_;
    my $running_ps = 0;

    foreach my threads $th (@$threads)
    {
        my $running = $th->is_running();
        $running_ps++ if ($running);
    }

    if( $running_ps > $max_threads )
    {
        # debug "Threads:\n\t Running: $running_ps\n\t Total: $#{$threads}";
        sleep 2;
        return 1;
    }
    return 0;
}

sub olt_is_down
{
    my $olt = shift;
    #Db->do("UPDATE pon_bind SET status='99:OLT_IS_DOWN:0', changed=UNIX_TIMESTAMP() WHERE olt_id=?", $olt->{id} );
}

sub init_pon
{
    my $olt = shift;
    # debug('pre', $olt);
    my $module = ucfirst(lc($olt->{vendor}));
    if( my $err = _load_module($module) )
    {
        debug 'error', $err;
        return 0; #$crit_err;
    }

    my $olt_main = ();
    $olt_main->{olt} = $olt;
    $olt_main->{onu_list} = &_get_onu_list() || {};
    $olt_main->{onu_bind} = &_get_bind() || {};
    $olt_main->{fdb} = &_get_fdb() || {};
    # debug('pre', $olt_main);
    my $Db = Db->connect;
    my $pon = "nod::Pon::$module";

    my $olt_data = $pon->main($olt, $M->{step});
    &_parse_olt_data( $olt_main, $olt_data );
    return;
}

sub _load_module
{
    my($name) = shift;
    $name = ucfirst(lc($name));
    debug "$cfg::dir_home/nod/Pon/$name.pm";
    eval{ require "$cfg::dir_home/nod/Pon/_$name.pm" };
    my $err = "$@";
    debug 'error', $err if $err && -e "$cfg::dir_home/nod/Pon/_$name.pm";
    $err && eval{ require "$cfg::dir_home/nod/Pon/$name.pm" };
    return "$@";
}

sub _parse_olt_data
{
    my $olt_main = shift;
    my $olt_data = shift;
    my $olt_id = $olt_main->{olt}{id};

    if( defined $olt_data->{fdb} )
    {
        foreach my $mac (sort keys %{$olt_data->{fdb}}) {
            foreach my $vlan (sort keys %{$olt_data->{fdb}{$mac}}) {
                foreach my $port (sort keys %{$olt_data->{fdb}{$mac}{$vlan}}) {
                    if (!defined $olt_main->{fdb}{$mac})
                    {
                        Db->do("INSERT INTO pon_fdb SET mac=?, vlan=?, llid=?, olt_id=?, time=UNIX_TIMESTAMP()",
                        $mac, $vlan, $port, $olt_id );
                    }
                    elsif (!defined $olt_main->{fdb}{$mac}{$vlan}{$port})
                    {
                        Db->do("UPDATE pon_fdb SET vlan=?, llid=?, olt_id=?, time=UNIX_TIMESTAMP() WHERE mac=?",
                        $vlan, $port, $olt_id, $mac );
                    }
                }
            }
        }
    }

    foreach my $sn (sort keys %{$olt_data->{onu_list}})
    {
        my $new_onu = $olt_data->{onu_list}{$sn};
        # debug('pre', $new_onu);
        $sn = uc($sn);
        if( !defined $olt_main->{onu_list}{$sn} )
        {
            my $new_onu = $olt_data->{onu_list}{$sn};
            Db->do("INSERT INTO pon_onu SET sn=?, changed=UNIX_TIMESTAMP()", $sn);
        }
        if( !defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}} )
        {
            Db->do("INSERT INTO pon_bind SET sn=?, olt_id=?, llid=?, tx=?, rx=?, status=?, dereg=?, changed=UNIX_TIMESTAMP()",
                $sn, $olt_id, $new_onu->{LLID}, $new_onu->{ONU_TX_POWER}, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_STATUS}, $new_onu->{DEREGREASON}
            );
        }
        else
        {
            # debug('pre',$new_onu);
            my $sql_query ='UPDATE pon_bind SET changed=UNIX_TIMESTAMP(),';
            my @sql_param = ();
            my $sql_where = " WHERE sn=? AND olt_id=? AND llid=? LIMIT 1";

            if ( defined $new_onu->{ONU_RX_POWER} && $new_onu->{ONU_RX_POWER} ne '' && sprintf("%.1f", $new_onu->{ONU_RX_POWER}) ne sprintf("%.1f", $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{rx}) )
            {
                $sql_query .= " rx=?,";
                push @sql_param, $new_onu->{ONU_RX_POWER};
            }
            if ( defined $new_onu->{ONU_TX_POWER} && $new_onu->{ONU_TX_POWER} ne '' && sprintf("%.1f", $new_onu->{ONU_TX_POWER}) ne sprintf("%.1f", $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{tx}) )
            {
                $sql_query .= " tx=?,";
                push @sql_param, $new_onu->{ONU_TX_POWER};
            }
            if ( defined $new_onu->{ONU_STATUS} && $new_onu->{ONU_STATUS} ne '' )
            {
                $sql_query .= " status=?,";
                push @sql_param, $new_onu->{ONU_STATUS};
            }
            elsif ( !defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{status})
            {
                $sql_query .= " status=?,";
                push @sql_param, '98:Unknown:0';
            }
            if ( defined $new_onu->{DEREGREASON} && $new_onu->{DEREGREASON} ne $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{dereg})
            {
                $sql_query .= " dereg=?,";
                push @sql_param, $new_onu->{DEREGREASON};
            }
            $sql_query =~ s/\,$//g;
            Db->do( $sql_query.$sql_where, @sql_param, $sn, $olt_id, $new_onu->{LLID}) if scalar @sql_param;
        }
    }
}

sub _get_ports
{
    my $db = Db->sql("SELECT * FROM `pon_ports` WHERE 1");
    while( my %p = $db->line )
    {
    #    $M{ports}{$p{olt_id}}{$p{p_index}} = \%p;
    }
    # debug('pre', $M{ports});
    #exit;
}

sub _get_bind
{
    my %onu_bind = ();
    my $db = Db->sql("SELECT * FROM pon_bind");
    while( my %p = $db->line )
    {
        $onu_bind{$p{sn}}{$p{olt_id}}{$p{llid}} = \%p;
    }
    return \%onu_bind;
}

sub _get_fdb
{
    my %fdb_cache = ();
    my $db = Db->sql("SELECT * FROM pon_fdb");
    while( my %p = $db->line )
    {
        $fdb_cache{$p{mac}}{$p{vlan}}{$p{llid}} = \%p;
    }
    return \%fdb_cache;
}

# https://local.com.ua/forum/topic/89848-olt-stels-snmp/
# https://tuxnotes.com/snippet/bdcom-snmp-oid

sub _get_onu_list
{
    my %onu_list = ();
    my $db = Db->sql("SELECT * FROM pon_onu WHERE 1");
    while( my %p = $db->line )
    {
        $onu_list{$p{sn}} = \%p;
    }
    return \%onu_list;
}


sub hash_merge
{
    my ($left, $right) = (shift, shift);
    foreach my $key (keys %$right) {
        if (!exists $left->{$key} || $left->{$key} eq $key ||  $left->{$key} == $key ) {
            $left->{$key} = $right->{$key};
        }
        elsif (ref $left->{$key} eq 'HASH' && ref $right->{$key} eq 'HASH') {
            $left->{$key} = &hash_merge($left->{$key}, $right->{$key});
        }
        elsif (ref $left->{$key} ne 'HASH') {
            print ref $left->{$key}, "\n\n\n";
        }
        # debug('pre',$left);
    }
    return $left;
}


sub _bind_fdb
{
    my %fdb_cache = ();
    {
        my $db = Db->sql("SELECT * FROM `pon_fdb`");
        $db->rows or return;
        while( my %p = $db->line )
        {
            $fdb_cache{$p{mac}} = \%p;
        }
    }

    my $db = Db->sql("SELECT * FROM `v_ips` WHERE `auth`=1");
    while( my %p = $db->line )
    {
        next if $p{properties} eq '';
        my %prop = map{ split /=/, $_, -1 } split /;/, $p{properties};
        if( my $mac = $prop{user} )
        {
            $mac =~ s/(..)(?=.)/$1:/g;
            if (defined $fdb_cache{uc($mac)})
            {
                next if $fdb_cache{uc($mac)}{uid} == $p{uid};
                Db->do("UPDATE pon_fdb SET uid=?, ip=? WHERE mac=?", $p{uid}, $p{ip}, $mac );
            }
        }
    }
}

sub _clean_history
{
    Db->do("DELETE FROM pon_mon WHERE `time` < UNIX_TIMESTAMP(NOW() - INTERVAL ? DAY)", $history_period) if $history_period;
}

1;
