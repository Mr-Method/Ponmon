#<ACTION> file=>'web/ajOnuFdb.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor FDB
# NoDeny: rev. 718
# Update: 2025.11.01
# ------------------------------------------------------------
use strict;

sub go {
    my $domid = ses::input('domid');
    my $res = _proc($_[0], $domid);
    $res && push @$ses::cmd, {
        id   => $domid,
        data => $res,
    };
}

sub _proc {
    my ($Url, $domid) = @_;
    my $llid   = ses::input('llid');
    my $olt_id = ses::input_int('olt_id');
    my $clear  = ses::input_int('clear') || 0;
    my $admin  = Adm->chk_privil('SuperAdmin') || Adm->chk_privil('Admin') || Adm->chk_privil(1204);
    $admin or return $lang::err_no_priv;

    if ($clear == 1) {
        my $block_domid = ses::input('block_id');
        my $clear_link = url->a(L('Очистити?'), a=>'ajOnuFdb', olt_id=>$olt_id, llid=>$llid, clear=>2, block_id=>$block_domid, -ajax=>1, -class=>'error');
        push @$ses::cmd, {
            id   => $domid,
            data => $clear_link,
        };
        return '';
    }
    if ($clear == 2) {
        Db->do("DELETE from pon_fdb WHERE llid=? AND olt_id=?", $llid, $olt_id);
        $domid = ses::input('block_id');
        push @$ses::cmd, {
            id   => $domid,
            data => '',
        };
    }

    my $db = Db->sql(
        "SELECT f.*, i.auth, i.ip as ipa FROM pon_fdb f LEFT JOIN v_ips i ON (i.uid = f.uid AND i.properties LIKE CONCAT('%user=', LOWER(REPLACE(`mac`,':','')),';%')) ".
        "WHERE olt_id=? AND llid=?", $olt_id, $llid
    );

    return '' if !$db->rows;

    my $user_field = Set_usr_field_line();
    my $tbl = tbl->new(-class=>'td_wide pretty');
    while (my %p = $db->line) {
        my $auth = $p{auth} ? [ v::tag('img', src=>$cfg::img_url.'/on.gif') ] : '';
        my $client = $p{uid} ? [ Show_usr_info($p{uid}, $user_field) ] : '';
        my $mac = $p{mac};
        $mac =~ s/(..)(?=.)/$1:/g if $mac !~ m/:/;
        $tbl->add($p{uid} ? '*' : 'rowoff', [
            [ '', L('Клиент'),   $client ],
            [ '', L('MAC'),      uc($mac) ],
            [ '', L('VLAN'),     $p{vlan} ],
            [ '', '',            $p{auth} ? [ v::tag('img', src=>$cfg::img_url.'/on.gif') ] : ''  ],
            [ '', L('IP'),       $p{ipa} ],
            [ '', L('Оновлено'), the_time($p{time}) ],
       ]);
    }
    my $link_domid = v::get_uniq_id();
    my $clear_link = url->a(L('Очистити'), a=>'ajOnuFdb', olt_id=>$olt_id, llid=>$llid, clear=>1, -id=>$link_domid, '-data-domid'=>$link_domid, block_id=>$domid, -ajax=>1);
    return WideBox(msg=>$tbl->show, title=>L('FDB кеш') . " | ${clear_link}");
}

1;
