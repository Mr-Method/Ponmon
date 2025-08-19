#<ACTION> file=>'web/ajUserOnu.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor user ONU
# NoDeny revision: 715
# Updated date: 2025.08.20
# ------------------------------------------------------------
use strict;

sub go {
    my $domid = ses::input('domid');
    push @$ses::cmd, {
        id   => $domid,
        data => _proc_user_onu($_[0], ses::input_int('uid'), $domid),
    };
}

sub _proc_user_onu {
    my ($Url, $uid, $domid) = @_;
    my $title = url->a(L('PON'), a=>'ajUserOnu', uid=>$uid, domid=>$domid, -ajax=>1);
    my $err_msg = Adm->why_no_usr_access($uid);
    $err_msg && return $err_msg;
    my %onu_list = ();
    if (!scalar %onu_list) { # pon_fdb
        my $db = Db->sql("SELECT b.*, f.mac, f.name AS fname FROM pon_bind b LEFT JOIN pon_fdb f ON (b.olt_id=f.olt_id AND b.llid=f.llid) WHERE f.uid=?", $uid);
        # "LEFT JOIN pon_olt o ON (o.id=f.olt_id) LEFT JOIN pon_onu t ON (t.sn=b.sn) "
        while (my %p = $db->line) {
            foreach my $key (keys %p) {
                $onu_list{$p{sn}}{bid}{$p{id}}{data}{$key} = $p{$key};
            }
            $onu_list{$p{sn}}{bid}{$p{id}}{mac}{$p{mac}} = 1 if $p{mac};
        }
    }
    if (!scalar %onu_list) { # place user
        my $db = Db->sql("SELECT b.*, o.sn FROM pon_onu o LEFT JOIN pon_bind b ON (b.sn=o.sn) WHERE o.place_type = 'user' AND o.place = ?", $uid);
        # "LEFT JOIN pon_olt o ON (o.id=f.olt_id) LEFT JOIN pon_onu t ON (t.sn=b.sn) "
        while (my %p = $db->line) {
            $p{id} ||= 0;
            map { $onu_list{$p{sn}}{bid}{$p{id}}{data}{$_} = $p{$_} } keys %p;
        }
    }
    if (!scalar %onu_list && !!$cfg::ponmon_web_user_sn_field) { # place user
        my $db = Db->sql(
            "SELECT b.*, d.".Db->filtr($cfg::ponmon_web_user_sn_field)." FROM pon_bind b ".
            "LEFT JOIN data0 d ON (b.sn=d.".Db->filtr($cfg::ponmon_web_user_sn_field).") WHERE d.uid = ?", $uid
        );
        # "LEFT JOIN pon_olt o ON (o.id=f.olt_id) LEFT JOIN pon_onu t ON (t.sn=b.sn) "
        while (my %p = $db->line) {
            $p{id} ||= 0;
            map { $onu_list{$p{sn}}{bid}{$p{id}}{data}{$_} = $p{$_} } keys %p;
        }
    }
    if (!scalar %onu_list && !!$cfg::ponmon_web_user_sn_field) { # place user
        my $db = Db->sql(
            "SELECT b.*, d.".Db->filtr($cfg::ponmon_web_user_sn_field)." FROM pon_onu b ".
            "LEFT JOIN data0 d ON (b.sn=d.".Db->filtr($cfg::ponmon_web_user_sn_field).") WHERE d.uid = ?", $uid
        );
        # "LEFT JOIN pon_olt o ON (o.id=f.olt_id) LEFT JOIN pon_onu t ON (t.sn=b.sn) "
        while (my %p = $db->line) {
            $p{id} = 0;
            map { $onu_list{$p{sn}}{bid}{$p{id}}{data}{$_} = $p{$_} } keys %p;
        }
    }
    if (!scalar %onu_list && !!$cfg::ponmon_web_places_object) { # place user
        my $db = Db->sql(
            "SELECT b.*, o.sn, d._adr_place FROM pon_bind b LEFT JOIN pon_onu o ON (b.sn=o.sn) ".
            "LEFT JOIN data0 d ON (o.place=d._adr_place) WHERE o.place_type = 'map' AND d.uid = ?", $uid
        );
        # "LEFT JOIN pon_olt o ON (o.id=f.olt_id ) LEFT JOIN pon_onu t ON (t.sn=b.sn) "
        while (my %p = $db->line) {
            $p{id} ||= 0;
            map { $onu_list{$p{sn}}{bid}{$p{id}}{data}{$_} = $p{$_} } keys %p;
        }
    }

#HOOK

    return '' if !scalar %onu_list;

    my %olt = ();
    my $olt_list = Db->sql("SELECT * FROM `pon_olt` WHERE 1");
    while (my %p = $olt_list->line) {
        $p{cfg} = Debug->do_eval($p{param}) || {};
        delete $p{param};
        $olt{$p{id}} = \%p;
    }
#    debug 'pre', \%olt;

    my $tbld = tbl->new(-class=>'td_medium td_ok width100 userOnuDesktop');#, -head=>'row3');
    my $tblm = tbl->new(-class=>'td_medium td_ok width100 userOnuMobile');#, -head=>'row3');
    foreach my $sn (sort keys %onu_list) {
        debug 'pre', $onu_list{$sn};
        foreach my $bid (sort keys %{$onu_list{$sn}{bid}}) {
            my $macs = '';
            foreach my $mac (sort keys %{$onu_list{$sn}{bid}{$bid}{mac}}) {
                $mac =~ s/(..)(?=.)/$1:/g if $mac !~ m/:/;
                $macs .= _('[dt]', uc($mac));
            }
            $macs = length $macs > 10 ? _('[dl]', $macs) : '';
            my $onu = $onu_list{$sn}{bid}{$bid}{data};
            #debug 'pre', $onu;
            my $info   = $bid && (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1202)) ? [ url->a('INFO', a=>'ponmon', act=>'edit', bid=>$bid, -class=>'nav') ] : '';
            my $sn     = defined $onu->{fname} ? _('[dl]', _('[dt][dt]', $sn, $onu->{fname})) : $sn;
            my $oname  = defined $onu->{olt_id} && defined $olt{$onu->{olt_id}} ? "$olt{$onu->{olt_id}}{name}" : '';
            my $status = defined $onu->{status} ? $onu->{status} : $bid ? '0::0' : '0:Not binded:0';
            my $time   = defined $onu->{changed} ? the_time($onu->{changed}) : '';
            my $signal = defined $onu->{rx} || defined $onu->{tx} ? _('[dl]', _('[dt][dt]', L('RX').': '.$onu->{rx},L('TX').': '.$onu->{tx})) : '';
            my ($s, $t, $v) = split /\:/, $status;
            $tbld->add($v ? '*' : 'rowoff', [
                [ '',           '',                     $info ],
                [ '',           L('ONU'),               [$sn] ],
                [ '',           L('OLT'),               $oname ],
                [ '',           L('Status'),            "$t($s)" ],
                [ '',           L('dBm'),               [$signal] ],
                [ '',           L('Updated'),           $time ],
                [ '',           L('MACs'),              [$macs] ],
            ]);
            $tblm->add($v ? '*' : 'rowoff', 'llll', $info, [$oname.'<hr>'.$sn], ["$t($s)".'<hr>'.$signal], [$time.'<hr>'.$macs]);
        }
    }
    my $style = _('[style]', '@media (max-width:600px){.userOnuMobile{display:table}.userOnuDesktop{display:none}}@media (min-width:601px){.userOnuMobile{display:none}.userOnuDesktop{display:table}}');

    return WideBox(msg => $style . $tbld->show . $tblm->show, title => $title);
}

1;
