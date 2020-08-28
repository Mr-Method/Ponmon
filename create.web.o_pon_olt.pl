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
    name_full   => 'OLT',
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

sub o_start
{
    $cfg::dir_vendors = "$cfg::dir_home/nod/Pon";
    my %Modules = ();
    $new->{_vendors} = \%Modules;

    opendir(my $dh, $cfg::dir_vendors) or Error_Lang(
        'Не могу прочитать каталог: [filtr|p]Если существует - проверьте права доступа.',
        $cfg::dir_vendors
    );

    # В 2 этапа, поскольку нужно исключить основные файлы, если у них есть фантомы
    while( my $module = readdir($dh) )
    {
        $module =~ s/^_?(.+)\.pm$/$1/ or next;
        $Modules{$module} = {};
    }
    closedir $dh;
    keys %Modules or Error_Lang('Нет ни одного модуля вендора (файла *.pm) в каталоге: [filtr|p]', $cfg::dir_vendors);

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

    while( my %p = $db->line )
    {
        my $alive = $p{status} ? L('on') : L('off');
        $tbl->add($p{enable} ? '*' : 'rowoff', [
            [ 'h_right',    'id',            $p{id} ],
            # [ 'h_center',   L('Сортировка'), $sort ],
            [ '',           L('Имя'),               $p{name} ],
            [ '',           L('Тип'),               $p{pon_type} ],
            [ '',           L('Вендор'),            $p{vendor} ],
            [ '',           L('Model'),             $p{model} ],
            [ '',           L('IP Адрес'),          $p{ip} ],
            [ '',           L('SNMP порт'),         $p{snmp_port} ],
            [ '',           L('Статус'),            $alive ],
            [ '',           '',                     $d->btn_edit($p{id}) ],
            [ '',           '',                     $d->btn_copy($p{id}) ],
            [ '',           '',                     $d->btn_del($p{id}) ],
        ]);
    }
    Show $tbl->show;
}

sub o_new {
    my($d) = @_;
}

sub o_edit
{
    my($d) = @_;
    $d->{name_full} = _('[] [filtr|commas] № [filtr]', $new->{name}, $d->{d}{name}||L('без адреса'), $d->{d}{id});
    # запрет на удаление
}

sub o_show
{
    my($d) = @_;
    my @menu = ();
    my $tbl = tbl->new( -class=>'td_ok pretty wide_input' );

    Doc->template('top_block')->{urls} .= ' '.url->a('help', a=>'help', theme=>'pon_mng',);

    debug('pre', $d->{_vendors});

    my @vendorlist = ();
    foreach my $key (sort keys %{$d->{_vendors}})
    {
        push @vendorlist, $key, $key;
    }

    my $vendors = v::select(
        name     => 'vendor',
        size     => 1,
        options  => \@vendorlist,
        selected => $d->{d}{vendor},
    );

    my @pon_types = (
        'epon','epon',
        'gpon','gpon',

#<HOOK>pon_types

    );

    my $pontype = v::select(
        name     => 'pon_type',
        #size     => 1,
        options  => \@pon_types,
        selected => $d->{d}{pon_type},
    );

    my @documents =(0,'');
    {
        my $db = Db->sql("SELECT * FROM documents WHERE is_section=0 AND tags LIKE '%,system,%' AND tags LIKE '%,pon_tmpl,%' ORDER BY name ASC");
        Db->rows or ToTop( L('У Вас нет шаблонов управления, обратитесь к странице "help"'));
        while( my %p = $db->line )
        {
            push @documents, $p{id}, $p{name};
        }
    }

    my $mng_tmpl = v::select(
        name     => 'mng_tmpl',
        size     => 1,
        options  => \@documents,
        selected => $d->{d}{mng_tmpl},
    );

    $tbl->add('', 'll', [ v::input_t(name=>'name', value=>$d->{d}{name}) ],                     L('name'), );
    $tbl->add('', 'll', [ $vendors ],                                                           L('vendor'), );
    $tbl->add('', 'll', [ v::input_t(name=>'model', value=>$d->{d}{model}) ],                   L('model'), );
    $tbl->add('', 'll', [ v::input_t(name=>'firmware', value=>$d->{d}{firmware}) ],             L('firmware'), );

    $tbl->add('', 'll', [ v::input_t(name=>'ip', value=>$d->{d}{ip}) ],                         L('IP'), );
    $tbl->add('', 'll', [ v::input_t(name=>'snmp_port', value=>$d->{d}{snmp_port}) ],           L('SNMP Port'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'ro_comunity', value=>$d->{d}{ro_comunity}) ],       L('ro_comunity'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_t(name=>'rw_comunity', value=>$d->{d}{rw_comunity}) ],       L('rw_comunity'), ) if Adm->chk_privil('SuperAdmin');

    $tbl->add('','ll',  [ $pontype ],                                                           L('pon_type'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ $mng_tmpl ],                                                          L('Management template'), ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', [ v::input_ta('descr', $d->{d}{descr}, 36, 6) ],                        L('Комментар'), );
    $tbl->add('', 'rl', [ v::checkbox( name=>'enable', value=>1, checked=>$d->{d}{enable}) ],   L('Увімкнути'), );

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

    $d->{sql} .= 'SET name=?, vendor=?, model=?, firmware=?, ip=?, snmp_port=?, ro_comunity=?, rw_comunity=?, pon_type=?, mng_tmpl=?, descr=?, enable=?, changed=UNIX_TIMESTAMP()';

    push @{$d->{param}}, v::trim(ses::input('name'));
    push @{$d->{param}}, ses::input('vendor');
    push @{$d->{param}}, ses::input('model');
    push @{$d->{param}}, ses::input('firmware');

    push @{$d->{param}}, v::trim(ses::input('ip'));
    push @{$d->{param}}, ses::input_int('snmp_port');
    push @{$d->{param}}, ses::input('ro_comunity');
    push @{$d->{param}}, ses::input('rw_comunity');

    push @{$d->{param}}, ses::input('pon_type');
    push @{$d->{param}}, ses::input_int('mng_tmpl');

    push @{$d->{param}}, v::trim(ses::input('descr'));
    push @{$d->{param}}, ses::input_int('enable');
}

sub o_insert
{
    return o_update(@_);
}

1;
