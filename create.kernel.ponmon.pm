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

use Net::Ping;
use Time::localtime;
use Parallel::ForkManager;

$SIG{CHLD} = 'IGNORE';
our @ISA = qw{kernel};

$cfg::_tbl_name_template = 'z%d_%02d_%02d_pon';

# Таблица суточного мониторинга
$cfg::_slq_create_zpon_table.=<<SQL;
(
  `bid` mediumint(7) NOT NULL,
  `tx` char(6) DEFAULT NULL,
  `rx` char(6) DEFAULT NULL,
  `time` int(11) NOT NULL DEFAULT '0',
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
SQL

my $step = 0;
my %onu_list = ();
my $period = int($cfg::k_ponmon_period) || 10;
my $running_threads = int($cfg::k_ponmon_max_threads) || 10;
my $history_period = int($cfg::k_ponmon_max_history) || 60;

sub start
{
    my(undef, $single, $config) = @_;
    my %forks = ();
    my $pm = Parallel::ForkManager->new($running_threads);

    nod::tasks->new(
        task         => sub{ main($_[0], $single, $config, $pm, \%forks ) },
        period       => $period * 60,
        first_period => $single? 0 : $period * 60,
    );
}

sub main
{
    my($task, $single, $config, $pm, $forks) = @_;
    $pm->is_parent or return;
    $pm->reap_finished_children;
    $step++;
    #debug 'pre', $forks;
    tolog( "STEP $step START! PID [$$] with running kids: ".scalar %$forks );
    my @pids = $pm->running_procs;
    if ( scalar @pids ) {
        for my $pid ( $pm->running_procs ) {
            if ( $forks->{$pid}{'time'} + ( $period * 120 ) < time ) {
                kill 'KILL', $pid;
            }
        }
    } else {
        undef %$forks;
    }

    Db->connect;
    my $db = Db->sql("SELECT * FROM `pon_olt` WHERE `enable` = 1");
    my $rows = $db->rows || 0;
    if (!$rows) {
        tolog( "ERROR: DB \t===> No OLT in DB!!!" );
        sleep 60;
        return 0;
    }

    $pm->set_max_procs($rows*2);
    $pm->run_on_finish( sub {
        my ($pid, $exit_code, $ident) = @_;
        undef $forks->{$pid};
        print "** $ident just got out of the pool with PID $pid and exit code: $exit_code\n";
    });

    $pm->run_on_start( sub {
        my ($pid, $ident)=@_;
            $forks->{$pid}{'time'} = time;
            $forks->{$pid}{'step'} = $step;
        print "** $ident started, pid: $pid\n";
    });

    &_sort_history();
    &_clean_history() if $history_period;

    #$SIG{'INT'} = sub { map{ $PonQueue->enqueue(0) } 1..$running_threads; };
    #$SIG{TERM} = sub { map{ $PonQueue->enqueue(0) } 1..$running_threads; };

    my $np = Net::Ping->new();
    WORK:
    while ( my %p = $db->line ) {
        # Forks and returns the pid for the child:
        $pm->start and next WORK;

        sleep 2;
        $0 = "nodeny::".__PACKAGE__;
        &init_pon({olt=>\%p, step=>$step, timeout=>480});
        $pm->finish; # Terminates the child process
    }
}

sub _document
{
    my $mng_tmpl = shift;
    my %settings = ();
    return \%settings if !$mng_tmpl;
    my %p = Db->line('SELECT document FROM documents WHERE id=? AND is_section=0', $mng_tmpl );
    %p or return \%settings;
    $p{document} =~ s/\r//gm;
    foreach my $line ( split /\n/, $p{document} ) {
        chomp($line);
        $line =~ /([^=\s]+)\s*=\s*(.+)/ or next;
        $settings{$1} = $2;
    }
    chomp(%settings);
    return \%settings;
}

sub init_pon
{
    my $work = shift;
    $0 = "nodeny::".__PACKAGE__;
    local $SIG{ALRM} = sub {
        local $SIG{TERM} = 'IGNORE';
        kill TERM => -$$;
        die "CHILD PID [$$] [$0] DIE BY TIMEOUT!\n";
    };
    #local $SIG{ALRM} = sub {  die "CHILD PID [$$] [$0] DIE BY TIMEOUT!"};
    alarm($work->{timeout});
    $0 = "nodeny::".__PACKAGE__;
    my $olt = $work->{olt};
    Db->connect;
    $olt->{cfg} = &_document($olt->{'mng_tmpl'});
    # debug('pre', $olt);
    my $step = $work->{step};

    tolog( "STEP->$step; OLT id $olt->{id} : START" );
    my $module = ucfirst(lc($olt->{vendor}));
    if( my $err = _load_module($module) )
    {
        tolog( "ERROR: OLT id $olt->{id} ===>\t $err" );
        die;
    }

    my $pon = "nod::Pon::$module";

    my $olt_data = $pon->main($olt, $step);
    &_parse_olt_data( $olt_data, $olt );
    tolog( "STEP->$step; OLT id $olt->{id} : FINISH" );
    return;
}

sub _load_module {
    my($name) = shift;
    $name = ucfirst(lc($name));
    debug "$cfg::dir_home/nod/Pon/$name.pm";
    if (grep { $_ eq "$cfg::dir_home/nod/Pon/_$name.pm" } values %INC || grep { $_ eq "$cfg::dir_home/nod/Pon/$name.pm" } values %INC) {
        return;
    }
    eval{ require "$cfg::dir_home/nod/Pon/_$name.pm" };
    my $err = "$@";
    debug 'error', $err if $err && -e "$cfg::dir_home/nod/Pon/_$name.pm";
    $err && eval{ require "$cfg::dir_home/nod/Pon/$name.pm" };
    return "$@";
}

sub _parse_olt_data
{
    my $olt_data = shift;
    my $olt = shift;
    my $olt_main;
    my $olt_id = $olt->{id};

    if( defined $olt_data->{fdb} )
    {
        #$olt_main->{fdb} = &_get_fdb() || {};
        foreach my $port (sort keys %{$olt_data->{fdb}}) {
            foreach my $vlan (sort keys %{$olt_data->{fdb}{$port}}) {
                foreach my $mac (sort keys %{$olt_data->{fdb}{$port}{$vlan}}) {
                    my $xname = $olt_data->{fdb}{$port}{$vlan}{$mac} || '';
                    Db->do("INSERT INTO pon_fdb SET mac=?, vlan=?, llid=?, olt_id=?, name=?, time=UNIX_TIMESTAMP() ".
                        "ON DUPLICATE KEY UPDATE mac=?, vlan=?, llid=?, olt_id=?, name=?, time=UNIX_TIMESTAMP()",
                        $mac, $vlan, $port, $olt_id, $xname, $mac, $vlan, $port, $olt_id, $xname
                    );
                }
            }
        }
        &_bind_fdb();
    }

    if ( defined $olt_data->{onu_list}) {
        $olt_main->{onu_list} = &_get_onu_list() || {};
        $olt_main->{onu_bind} = &_get_bind() || {};
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
            Db->do("INSERT INTO pon_bind SET sn=?, olt_id=?, llid=?, tx=?, rx=?, status=?, changed=UNIX_TIMESTAMP() ".
                "ON DUPLICATE KEY UPDATE sn=?, olt_id=?, llid=?, tx=?, rx=?, status=?, changed=UNIX_TIMESTAMP()",
                $sn, $olt_id, $new_onu->{LLID}, $new_onu->{ONU_TX_POWER}, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_STATUS},
                $sn, $olt_id, $new_onu->{LLID}, $new_onu->{ONU_TX_POWER}, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_STATUS},
            );
        }
        else
        {
            # debug('pre',$new_onu);
            my $sql_query ='UPDATE pon_bind SET changed=UNIX_TIMESTAMP(),';
            my @sql_param = ();
            my $sql_where = " WHERE sn=? AND olt_id=? AND llid=? LIMIT 1";
            my $data = 0;
            if ( defined $new_onu->{ONU_RX_POWER} && $new_onu->{ONU_RX_POWER} ne '0' )
            {
                $data = 1;
                $sql_query .= " rx=?,";
                push @sql_param, $new_onu->{ONU_RX_POWER};
            } else { $new_onu->{ONU_RX_POWER} = '0' }
            if ( defined $new_onu->{ONU_TX_POWER} && $new_onu->{ONU_TX_POWER} ne '0' )
            {
                $data = 1;
                $sql_query .= " tx=?,";
                push @sql_param, $new_onu->{ONU_TX_POWER};
            } else { $new_onu->{ONU_RX_POWER} = '0' }
            if ( defined $new_onu->{ONU_STATUS} && $new_onu->{ONU_STATUS} ne '' )
            {
                $sql_query .= " status=?,";
                if ( $data && $new_onu->{ONU_STATUS} =~ m/\:0/) {
                    push @sql_param, '90:Unknown:1';
                } else {
                    push @sql_param, $new_onu->{ONU_STATUS};
                }
            } elsif ( !defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{status} ) {
                $sql_query .= " status=?,";
                push @sql_param, '98:Unknown:0';
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
    my $db = Db->sql("SELECT * FROM v_ips WHERE auth=1");
    while( my %p = $db->line )
    {
        next if $p{properties} eq '';
        my %prop = map{ split /=/, $_, -1 } split /;/, $p{properties};
        if( my $mac = $prop{user} )
        {
            $mac =~ s/(..)(?=.)/$1:/g;
            Db->do("UPDATE pon_fdb SET uid=?, ip=? WHERE mac=?", $p{uid}, $p{ip}, $mac );
        }
    }
}

sub _sort_history
{
    #my $sql = Db->sql("SELECT * FROM pon_mon WHERE time < UNIX_TIMESTAMP(CONCAT(CURDATE(), ' 00:00:00'))-1 ORDER BY time ASC" );
    my $sql = Db->sql("SELECT * FROM pon_mon ORDER BY time ASC" );
    my $oldtblname = '';
    while ( my %p = $sql->line ) {
         my $t = localtime($p{time});
         my ($day_now, $mon_now, $year_now) = ($t->mday, $t->mon, $t->year);
         my $traf_tbl_name = sprintf $cfg::_tbl_name_template, $year_now+1900, $mon_now+1, $day_now;
         debug $traf_tbl_name, "\n";
         if ($traf_tbl_name ne $oldtblname) {
             Db->do("CREATE TABLE IF NOT EXISTS $traf_tbl_name $cfg::_slq_create_zpon_table");
             $oldtblname = $traf_tbl_name;
         }
         Db->do("INSERT INTO $traf_tbl_name SET bid=?, tx=?, rx=?, time=?", $p{bid}, $p{tx}, $p{rx}, $p{time});
         Db->do("DELETE FROM `pon_mon` WHERE bid=? and time=?", $p{bid}, $p{time});
    }
}

sub _clean_history {
    Db->do("DELETE FROM pon_bind WHERE changed < UNIX_TIMESTAMP(NOW() - INTERVAL 7 DAY)");
    Db->do("DELETE FROM pon_fdb WHERE time < UNIX_TIMESTAMP(NOW() - INTERVAL 2 DAY)");
}

1;
