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
    $menu = $Url->a("All OLT: $counto", act=>'list', olt=>0 ) .$menu;
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
        $sql->[0] .= " AND sn LIKE '%".$sn."%'";
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

    my %p = Db->line('SELECT b.*, o.vendor, o.model, o.firmware, o.descr FROM `pon_bind` b LEFT JOIN pon_onu o ON (b.sn=o.sn) WHERE b.id=?', ses::input('bid') );
    my $tblc = tbl->new( -class=>'td_wide pretty' );

    my $domid2 = v::get_uniq_id();
    my $graph_btn = [ url->a(L('Графік'), a=>'ajOnuGraph', bid=>$p{id}, -ajax=>1) ]; # , '-data-ajax-into-here'=>1)
    my $dereg_btn = [ url->a('Dereg', a=>'ajOnuMenu', bid=>$p{id}, domid=>$domid2, -ajax=>1) ];
    my $reset_btn = [ url->a('Reboot', a=>'ajOnuMenu', bid=>$p{id}, domid=>$domid2, -ajax=>1) ];

    my ($s, $t, $v) = split /\:/, $p{status};
    $tblc->add( $v ? '*' : 'rowoff', [
        # [ '',           L('OLT'),         $pon{olt}{$p{olt_id}}{name} ],
        # [ '',           L('Имя'),         $p{name} ],
        [ '',           L('sn'),          $p{sn} ],
        [ '',           L('RX'),          $p{rx} ],
        [ '',           L('TX'),          $p{tx} ],
        [ '',           L('Status'),      "$t($s)" ],
        [ 'l',          L('LAST ERR'),    $p{dereg} ],
        [ '',           '',               $graph_btn ],
    ]);
    debug('pre', \%p);

    Show v::tag('div', id=>'a_onu_graph', -body=>'');
    Show $tblc->show;

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

    #ToRight $Url->form( id=>ses::input('id'), $tblr->show );

    $totop = _('[]: OLT: [bold]: ONU: [bold]', $totop, $pon{olt}{$p{olt_id}}{name}, $p{sn});
    Doc->template('top_block')->{title} = $totop;
}

sub pon_help
{
}

1;
