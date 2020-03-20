#<ACTION> file=>'web/o_pon_olt.pl',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
package op;
use strict;

my $new = {
    name        => L('Сервери OLT'),
    table       => 'pon_olt',
    field_id    => 'id',
    priv_show   => 'Admin',
    priv_edit   => 'SuperAdmin',
    priv_copy   => 'SuperAdmin',
    allow_copy  => 1,
    sql_get     => 'SELECT * FROM pon_olt WHERE id=? GROUP BY id',
    menu_create => L('Новий OLT'),
    menu_list   => L('Всі OLT'),
};

my %mng_type = {
    1        => 'ssh',
    2        => 'telnet',
};


my $Dictionary;

sub o_start
{
    main::Require_web_mod('Data') && die;
    $Dictionary = Data->dictionary;
    # exists $Dictionary->{oltvendor} or ToTop( url->a(
    #    'Создайте объект oltvendor',
    #    a=>'op', op=>'new', act=>'dictionary', type=>'oltvendor',
    # ));
    return $new;
}

sub o_list
{
    my($d) = @_;
    my $tbl = tbl->new( -class=>'td_wide pretty', -head=>'head', -row1=>'row3', -row2=>'row3' );
    my $url = $d->{url}->new();

    my $sql_where = 'WHERE 1';
    my @sql_param = ();

    Doc->template('top_block')->{title} = L('Сервери OLT');

    my $db = Db->sql("SELECT * FROM pon_olt $sql_where ORDER BY id", @sql_param);

    my %type = @{$Dictionary->{placetype} || []};

    while( my %p = $db->line )
    {
        my $id = $p{id};
        my $alive = $p{status} ? L('on') : L('off');
        $tbl->add($p{enable} ? '*' : 'rowoff', [
            [ 'h_right',    'id',            $id ],
            # [ 'h_center',   L('Сортировка'), $sort ],
            [ '',           L('Имя'),               $p{name} ],
            [ '',           L('Вендор'),            $p{vendor} ],
            [ '',           L('Model'),             $p{model} ],
            [ '',           L('IP Адрес'),          $p{ip} ],
            [ '',           L('SNMP порт'),         $p{snmp_port} ],
            [ '',           L('Статус'),            $alive ],
            [ '',           '',                     $d->btn_edit($id) ],
            [ '',           '',                     $d->btn_copy($id) ],
            [ '',           '',                     $d->btn_del($id) ],
        ]);
    }
    Show $tbl->show;
}

sub o_edit
{
    my($d) = @_;
    $d->{name_full} = _('[] [filtr|commas] № [filtr]', $new->{name}, $d->{d}{name}||L('без адреса'), $d->{d}{id});
    # запрет на удаление
}

sub o_new {}

sub o_show
{
    my($d) = @_;
    my @menu = ();
    my $tbl = tbl->new( -class=>'td_ok pretty wide_input' );


    if( exists $Dictionary->{oltvendor} )
    {
        my %type = @{$Dictionary->{oltvendor}};
        map{ $_ = $_->{v} } values %type;
        $type{''} = '';
        my $type_list = v::select(
            name     => 'oltvendor',
            size     => 1,
            options  => \%type,
            selected => $d->{d}{oltvendor},
        );
        $tbl->add('','ll', [ $type_list ], L('oltvendor'));
    }

    my $mngtype = v::select(
        name     => 'mng_type',
        size     => 1,
        options  => \%mng_type,
        selected => $d->{d}{mng_type},
    );


    $tbl->add('', 'll', [ v::input_t(name=>'name', value=>$d->{d}{name}) ],					L('name'), );
    $tbl->add('', 'll', [ v::input_t(name=>'vendor', value=>$d->{d}{vendor}) ],				L('vendor'), );
    $tbl->add('', 'll', [ v::input_t(name=>'model', value=>$d->{d}{model}) ],					L('model'), );
    $tbl->add('', 'll', [ v::input_t(name=>'firmware', value=>$d->{d}{firmware}) ],			L('firmware'), );

    $tbl->add('', 'll', [ v::input_t(name=>'ip', value=>$d->{d}{ip}) ],						L('IP'), );
    $tbl->add('', 'll', [ v::input_t(name=>'snmp_port', value=>$d->{d}{snmp_port}) ],          L('SNMP Port'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'ro_comunity', value=>$d->{d}{ro_comunity}) ],      L('ro_comunity'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'rw_comunity', value=>$d->{d}{rw_comunity}) ],      L('rw_comunity'), ) if Adm->chk_privil('SuperAdmin');

    # $tbl->add('','ll',  [ $mngtype ],        L('mng_type'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'mng_user', value=>$d->{d}{mng_user}) ],			L('mng_user'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'mng_pswd', value=>$d->{d}{mng_pswd}) ],			L('mng_pswd'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_ta('descr', $d->{d}{descr}, 36, 6) ],						L('Комментар'), );
    $tbl->add('', 'rl', [ v::checkbox( name=>'enable', value=>1, checked=>$d->{d}{enable}) ],	L('Увімкнути'), );

    if( $d->chk_priv('priv_edit') )
    {
        $tbl->add('','C', [ v::submit($lang::btn_save) ]);
        push @menu, '<br>', $d->{url}->a($lang::btn_delete, op=>'del');
    }

    Show $d->{url}->form( id=>$d->{id}, $tbl->show );

    ToRight _('[div bigpadding navmenu]', join('', @menu));
}

sub o_update
{
    my($d) = @_;

    $d->{sql} .= 'SET name=?, vendor=?, model=?, firmware=?, ip=?, snmp_port=?, ro_comunity=?, rw_comunity=?, mng_user=?, mng_pswd=?, descr=?, enable=?, changed=UNIX_TIMESTAMP()';

    push @{$d->{param}}, v::trim(ses::input('name'));
    push @{$d->{param}}, ses::input('vendor');
    push @{$d->{param}}, ses::input('model');
    push @{$d->{param}}, ses::input('firmware');

    push @{$d->{param}}, v::trim(ses::input('ip'));
    push @{$d->{param}}, ses::input('snmp_port') + 0;
    push @{$d->{param}}, ses::input('ro_comunity');
    push @{$d->{param}}, ses::input('rw_comunity');

    #push @{$d->{param}}, ses::input('mng_type');
    push @{$d->{param}}, ses::input('mng_user');
    push @{$d->{param}}, ses::input('mng_pswd');

    push @{$d->{param}}, v::trim(ses::input('descr'));
    push @{$d->{param}}, ses::input('enable') + 0;
}

sub o_insert
{
    return o_update(@_);
}

1;
