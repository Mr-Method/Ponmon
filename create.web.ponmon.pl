#<ACTION> file=>'web/ponmon.pl',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
use strict;
use Debug;

use JSON;
use Time::Local;
use Time::localtime;

main::Require_web_mod('Data') && die;

my %pon = (
    status => {
        0 => 'logging',
        1 => 'LOS',
        2 => 'Synchronization',
        3 => 'Online',
        4 => 'DyingGasp',
        5 => 'Power_Off',
        6 => 'Offline',
    },
);

my $totop = 'PON monitor';

sub go
{
    my($Url) = @_;
    my $super_priv = Adm->chk_privil('SuperAdmin') && $ses::auth->{trust};
    my %subs = (
       list        => 1,    # просмотр карточек
       edit        => 1,
       del         => 1,
       help        => 1,
    );

    my $act = ses::input('act');

    $act = 'help' if ! $subs{$act};
    $Url->{act} = $act;
    my $menu = '';
    my $db = Db->sql('SELECT o.*, (SELECT COUNT(*) FROM pon_bind WHERE olt_id = o.id) AS binds FROM pon_olt o ORDER BY o.id ASC');
    my $counto = 0;
    while( my %p = $db->line )
    {
        $pon{olt}{$p{id}}=\%p;
        $menu .= $Url->a("$p{name} ($p{vendor}-$p{model}): $p{binds}", act=>'list', olt=>$p{id} );
        $counto += $p{binds};
    }
    $menu = $Url->a("All OLT: $counto", act=>'list', olt=>0 )."<hr>" .$menu ."<hr>";
    $menu .= $Url->a("Manage OLTs", act=>'pon_olt', a=>'op' );
    $menu && ToLeft Menu($menu);
    # my $search_block = '';
    ToLeft Menu($Url->form( act=>'list',
        [
            {type => 'text', value => ses::input('sn'), name => 'sn', title => 'onu sn'},
            {type => 'submit', value => 'search'},
        ]
    ));

    $main::{'pon_'.$act}->($Url, $act, $super_priv);
}

# =====================================
#    Список
# =====================================
sub pon_list
{
    my($Url, $act, $super_priv) = @_;
    $totop .= ': list';

    my $sql = ['SELECT * FROM pon_bind WHERE 1 '];
    my $olt=ses::input_int('olt') || 0;

    if( $olt )
    {
        $sql->[0] .= " AND olt_id=?";
        push @$sql, $olt;
        $Url->{olt} = $olt;
        $totop = _('[] OLT ID: [bold]', $totop, $olt);
    }

    if( defined ses::input('sn'))
    {
        my $sn = Db->filtr(uc(ses::input('sn')));
        my $mac = $sn;
        $mac =~ s/[-:\.]//g;
        $mac =~ s/(..)(?=.)/$1:/g;
        $sql->[0] .= " AND (sn LIKE '%".$sn."%' OR sn LIKE '%".$mac."%')";
        $Url->{sn} = $sn;
    }

    my $tbl = tbl->new( -class=>'td_wide pretty width100' );
    my ($sql, $page_buttons, $rows, $db) = main::Show_navigate_list($sql, ses::input_int('start'), 50, $Url);

    if( $rows < 1 )
    {
        Show main::Box( msg=>'По фильтру onu не найдены' , css_class=>'big bigpadding');
        return;
    }
    while( my %p = $db->line )
    {
        #debug('pre', $onu);
        #my $domid = v::get_uniq_id();
        #my $info = [ url->a('info', a=>'ajOnu', oid=>$id, domid=>$domid, -ajax=>1) ];

        my ($s, $t, $v) = split /\:/, $p{status};
        $tbl->add( $v ? '*' : 'rowoff', [
            [ 'h_center',   L('Info'),        [ $Url->a('INFO', act=>'edit', bid=>$p{id}, -class=>'nav') ] ],
            [ '',           L('OLT'),         $pon{olt}{$p{olt_id}}{name} ],
            #[ '',           L('Имя'),          $p{name} ],
            [ '',           L('sn'),          $p{sn} ],
            #[ '',           L('Vendor'),       $onu->{vendor} ],
            #[ '',           L('Model'),        $onu->{model} ],
            [ '',           L('RX'),          $p{rx} ],
            [ '',           L('TX'),          $p{tx} ],
            #[ '',           L('Ver'),          $onu->{firmware} ],
            [ '',           L('Status'),      "$t($s)" ],
            [ '',           L('LAST ERR'),    $p{dereg} ],
            [ '',           L('LAST CHANGE'), the_time($p{changed}) ],
       ]);
    }

    Doc->template('top_block')->{title} = $totop;
    Show $page_buttons.$tbl->show.$page_buttons;
}

sub pon_edit
{
    my($Url, $act, $super_priv) = @_;
    my $url = $Url;
    my ($domid, $domid_uinfo) = (v::get_uniq_id(), v::get_uniq_id());
    my $fields = Data::fields->new(0, ['d'], { _adr_place => 1 });
    my @buttons = ();

    my $Ftm_stat = ses::input_int('tm_stat') || $ses::t;
    $Ftm_stat = $ses::t if $Ftm_stat > 1956513600; # не больше 2032г. - мало ли как mysql поведет себя...
    $url->{tm_stat} = $Ftm_stat if ses::input_exists('tm_stat');
    $url->{bid} = ses::input_int('bid') if ses::input_exists('bid');

    my %p = Db->line('SELECT b.*, o.vendor, o.model, o.firmware, o.descr FROM `pon_bind` b LEFT JOIN pon_onu o ON (b.sn=o.sn) WHERE b.id=?', ses::input('bid') );
    my $tblc = tbl->new( -class=>'td_wide pretty' );

    my $domid2 = v::get_uniq_id();
    my $dereg_btn = [ url->a('Dereg', a=>'ajOnuMenu', bid=>$p{id}, domid=>$domid2, -ajax=>1) ];
    my $reset_btn = [ url->a('Reboot', a=>'ajOnuMenu', bid=>$p{id}, domid=>$domid2, -ajax=>1) ];
    ToLeft MessageWideBox( Get_list_of_stat_days('Z', $url, $Ftm_stat) );

    my ($s, $t, $v) = split /\:/, $p{status};
    $tblc->add( $v ? '*' : 'rowoff', [
        # [ '',           L('OLT'),         $pon{olt}{$p{olt_id}}{name} ],
        # [ '',           L('Имя'),         $p{name} ],
        [ '',           L('sn'),          $p{sn} ],
        [ '',           L('RX'),          $p{rx} ],
        [ '',           L('TX'),          $p{tx} ],
        [ '',           L('Status'),      "$t($s)" ],
        # [ 'l',          L('LAST ERR'),    $p{dereg} ],
        [ '',           L('LAST CHANGE'), the_time($p{changed}) ],
        [ '',           '',               $graph_btn ],
    ]);
    debug('pre', \%p);

    Show v::tag('div', id=>'a_onu_graph', -body=>'');
    Show WideBox( msg=>$tblc->show, title=>L('BIND info') );

    my $tblr = tbl->new( -class=>'td_ok pretty wide_input' );

    $tblr->add('', 'll', [ v::input_t(name=>'name',     value=>$p{name}) ],     L('name'), );
    $tblr->add('', 'll', [ v::input_t(name=>'vendor',   value=>$p{vendor}) ],   L('vendor'), );
    $tblr->add('', 'll', [ v::input_t(name=>'model',    value=>$p{model}) ],    L('model'), );
    $tblr->add('', 'll', [ v::input_t(name=>'firmware', value=>$p{firmware}) ], L('firmware'), );
    $tblr->add('', 'll', [ v::input_ta(name=>'descr',   $p{descr}, 8, 2) ],     L('Комментар'), );

    $tblr->add('', 'lL', [ $fields->get_field('_adr_place')->form(iname=>'place') ],            L('Точка топологии'), );
    $tblr->add('v_top', 'lll',  [ v::tag('input', type=>'hidden',  name=>'client', value=>$p{client} || '',
        id=>$domid, 'data-autoshow-userinfo'=>$domid_uinfo).v::tag('div', id=>$domid_uinfo) ],
        [ url->a(L('С кем связано'), a=>'user_select', -separator=>'&', -class=>'new_window', '-data-parent'=>$domid) ], );

    my $db = Db->sql('SELECT b.*, i.auth FROM pon_fdb b LEFT JOIN v_ips i ON (i.ip = b.ip) WHERE olt_id=? AND llid=?', $p{olt_id}, $p{llid} );
    my $tbl = tbl->new( -class=>'td_wide pretty' );
    while( my %p = $db->line )
    {
        #my $auth = $p{auth} ?  v::tag('img', src=>$cfg::img_url.'/on.gif') : '';
        #my $col_auth = $p{state} eq 'on'? 'on.gif' : '';
        my $auth = $p{auth} ? [ v::tag('img', src=>$cfg::img_url.'/on.gif') ] : '';
        my $client = $p{uid} ? [ Show_usr_info($p{uid}, 'adr') ] : '';

        $tbl->add( $v ? '*' : 'rowoff', [
            [ '',           L('Клиент'),      $client ],
            [ '',           L('mac'),         $p{mac} ],
            [ '',           L('vlan'),        $p{vlan} ],
            [ '',           '',               $p{auth} ? [ v::tag('img', src=>$cfg::img_url.'/on.gif') ] : ''  ],
            [ '',           L('ip'),          $p{ip} ],
            [ '',           L('LAST CHANGE'), the_time($p{time}) ],
       ]);
    }

    Show WideBox( msg=>$tbl->show, title=>L('FDB CACHE') ) if $db->rows;
    $totop = _('[]: OLT: [bold]: ONU: [bold]', $totop, $pon{olt}{$p{olt_id}}{name}, $p{sn});
    Doc->template('top_block')->{title} = $totop;
}

sub Get_list_of_stat_days
{
    my($tbl_type, $url, $sel_time) = @_;
    my $dbh = Db->dbh;
    my $sth = $dbh->prepare('SHOW TABLES');
    $sth->execute or return '';
    my $t = localtime(int $sel_time);
    # строка для сравнения с днем, который необходимо выделить
    $sel_time = $t->mday.'.'.$t->mon.'.'.$t->year;
    debug("SHOW TABLES (Таблиц: ".$sth->rows.")");
    my %days;
    while ( my $p = $sth->fetchrow_arrayref )
    {
        $p->[0] =~ /^z(\d\d\d\d)_(\d+)_(\d+)_pon$/i or next;
        my $time = timelocal(59,59,23,$3,$2-1,$1); # конец дня
        $days{$time} = substr('0'.$3,-2,2).'.'.substr('0'.$2,-2,2).'.'.$1;
    }
    my $list_of_days = '';
    my $t1 = 0;
    my $t2 = 0;
    foreach my $time ( sort {$b <=> $a} keys %days )
    {
        my $t = localtime($time);
        my $day  = $t->mday;
        my $mon  = $t->mon;
        my $year = $t->year;
        if( $t1 != $mon || $t2 != $year )
        {
            $t1 = $mon;
            $t2 = $year;
            $list_of_days .= _('[p]&nbsp;', $lang::month_names[$mon+1].' '.($year+1900).':');
        }
        #$list_of_days .= $url->a( $day, tm_stat=>$time, -active=>$sel_time eq "$day.$mon.$year" );
        $list_of_days .= url->a( $day, a=>'ajOnuGraph', bid=>ses::input_int('bid'), tm_stat=>$time, -ajax=>1 );
        $list_of_days .= $day==11 || $day==21? '<br>&nbsp;' : ' ';
    }
    return $list_of_days;
}

sub pon_help {}

1;
