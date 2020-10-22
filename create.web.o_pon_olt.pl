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
    sql_get     => 'SELECT * FROM pon_olt WHERE id=?',
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
    Doc->template('top_block')->{title} = $d->{name};
    my $tbl = tbl->new( -class=>'td_wide pretty', -head=>'head', -row1=>'row3', -row2=>'row3' );
    my $url = $d->{url}->new();

    my $sql_where = 'WHERE 1';
    my @sql_param = ();

    Doc->template('top_block')->{title} = L('Сервери OLT');

    my $db = Db->sql("SELECT * FROM pon_olt $sql_where ORDER BY id", @sql_param);

    while( my %p = $db->line )
    {
        $tbl->add($p{enable} ? '*' : 'rowoff', [
            [ 'h_right',    'id',            $p{id} ],
            # [ 'h_center',   L('Сортировка'), $sort ],
            [ '',           L('Имя'),               $p{name} ],
            [ '',           L('Тип'),               $p{pon_type} ],
            [ '',           L('Вендор'),            $p{vendor} ],
            [ '',           L('Model'),             $p{model} ],
            [ '',           L('IP Адрес'),          $p{ip} ],
            [ '',           L('SNMP порт'),         $p{snmp_port} ],
            [ '',           '',                     $d->btn_edit($p{id}) ],
            [ '',           '',                     $d->btn_copy($p{id}) ],
            [ '',           '',                     $d->btn_del($p{id}) ],
        ]);
    }
    Show $tbl->show;
}

sub o_new {
    my($d) = @_;
    $d->{d}{param} = {};
}

sub o_edit
{
    my($d) = @_;
    $d->{d}{param} = Debug->do_eval($d->{d}{param});
    if ( !$d->{d}{param} || $d->{d}{param} eq '' )
    {
        ToTop L('Внимание. Параметры не расшифрованы т.к. они повреждены');
        $d->{d}{param} = {};
    }

    $d->{name_full} = _('[] [filtr|commas] № [filtr]', $new->{name}, $d->{d}{name}||L('без адреса'), $d->{d}{id});
    # запрет на удаление
    #$d->{no_delete} = L('услуга подключена к [] клиентам', $d->{d}{now_count}) if $d->{d}{now_count}>0;
}

sub o_show
{
    my($d) = @_;
    my @menu = ();
    my %params = defined $d->{d}{param} ? %{$d->{d}{param}} : {};
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

    $tbl->add('', 'll', L('Увімкнути'),             [ v::checkbox( name=>'enable', value=>1, checked=>$d->{d}{enable}) ],   );
    $tbl->add('', 'll', L('name'),                  [ v::input_t(name=>'name', value=>$d->{d}{name}) ],                     );
    $tbl->add('', 'll', L('vendor'),                [ $vendors ],                                                           );
    $tbl->add('', 'll', L('model'),                 [ v::input_t(name=>'model', value=>$d->{d}{model}) ],                   );
    $tbl->add('', 'll', L('firmware'),              [ v::input_t(name=>'firmware', value=>$d->{d}{firmware}) ],             );

    $tbl->add('', 'll', L('IP'),                    [ v::input_t(name=>'ip', value=>$d->{d}{ip}) ],                         );
    $tbl->add('', 'll', L('SNMP Port'),             [ v::input_t(name=>'snmp_port', value=>$d->{d}{snmp_port}) ],           ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', L('ro_comunity'),           [ v::input_t(name=>'ro_comunity', value=>$d->{d}{ro_comunity}) ],       ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', L('rw_comunity'),           [ v::input_t(name=>'rw_comunity', value=>$d->{d}{rw_comunity}) ],       ) if Adm->chk_privil('SuperAdmin');

    $tbl->add('', 'll', L('pon_type'),              [ $pontype ],                                                           ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', L('Management template'),   [ $mng_tmpl ],                                                          ) if Adm->chk_privil('SuperAdmin');
    $tbl->add('', 'll', L('Комментар'),             [ v::input_ta('descr', $d->{d}{descr}, 36, 6) ],                        );
    $tbl->add('', 'C',  L('Додаткові параметри') );
    $tbl->add('', 'cc', L('ключ'), L('значення') );
    foreach my $key (sort keys %params)
    {
        if ( length($params{$key}) > 32)
        {
            $tbl->add('', 'cl', $key.' ', [ v::input_ta($key, $params{$key}, 60, 4) ]);
        }
        else
        {
            $tbl->add('*', 'cl', $key.' ', [ v::input_t(name=>$key, value=>$params{$key}, size=>16) ], );
        }
    }
    $tbl->add('', 'rl',[ v::input_t(name=>'key0', value=>'', size=>10) ], [ v::input_t(name=>'value0', value=>'', size=>20) ], );
    $tbl->add('', 'rl',[ v::input_t(name=>'key1', value=>'', size=>10) ], [ v::input_t(name=>'value1', value=>'', size=>20) ], );
    $tbl->add('', 'rl',[ v::input_t(name=>'key2', value=>'', size=>10) ], [ v::input_t(name=>'value2', value=>'', size=>20) ], );

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
    my %data = %{$ses::input_orig};
    delete $data{a}; delete $data{op}; delete $data{act}; delete $data{id};


    $d->{sql} .= 'SET name=?, vendor=?, model=?, firmware=?, ip=?, snmp_port=?, ro_comunity=?, rw_comunity=?, pon_type=?, mng_tmpl=?, descr=?, enable=?, param=?, changed=UNIX_TIMESTAMP()';

    push @{$d->{param}}, delete $data{name};
    push @{$d->{param}}, delete $data{vendor};
    push @{$d->{param}}, delete $data{model};
    push @{$d->{param}}, delete $data{firmware};

    push @{$d->{param}}, delete $data{ip};
    push @{$d->{param}}, delete $data{snmp_port};
    push @{$d->{param}}, delete $data{ro_comunity};
    push @{$d->{param}}, delete $data{rw_comunity};

    push @{$d->{param}}, delete $data{pon_type};
    push @{$d->{param}}, delete $data{mng_tmpl};

    push @{$d->{param}}, v::trim(delete $data{descr});
    push @{$d->{param}}, delete $data{enable};

    for my $kk (0..2)
    {
        my $key = defined $data{'key'.$kk} ? delete $data{'key'.$kk} : '';
        $key =~ s/\s//g;
        my $value = defined $data{'value'.$kk} ? delete $data{'value'.$kk} : '';
        next if $key eq '' || $value eq '';
        $data{$key} = $value;
    }
    foreach my $key (sort keys %data)
    {
         delete $data{$key} if !$data{$key};
    }

    my $param = Debug->dump(\%data);
    debug $param;
    push @{$d->{param}}, $param;
}

sub o_insert
{
    return o_update(@_);
}

sub o_predel
{
    my($d) = @_;
    $d->chk_priv('priv_edit') or $d->error_priv();
    $d->o_getdata();
    $d->o_edit();
    $d->{no_delete} && Error(L('Удаление [] заблокировано системой, поскольку []', $d->{name_full}, $d->{no_delete}));

    ses::input_int('now') or Error(
        _('[] [][hr space][div h_center]',
            L('Удаление'), $d->{name_full}, '', $d->{url}->form(op=>'del', id=>$d->{id}, now=>1, v::submit($lang::btn_Execute))
        )
    );

    my $ok = Db->do_all(
        [ "DELETE FROM $d->{table} WHERE $d->{field_id}=? LIMIT 1", $d->{id} ],
        [ "INSERT INTO changes SET act='delete', new_data='', time=UNIX_TIMESTAMP(), tbl=?, fid=?, adm=?, old_data=?",
            $d->{table}, $d->{id}, Adm->id, Debug->dump($d->{d}) ],
    );
    if ( $ok ) {
        Db->do("DELETE FROM pon_bind WHERE olt_id=? ", $d->{id} );
        Db->do("DELETE FROM pon_fdb WHERE olt_id=? ", $d->{id} );
    }
    $ok or Error(L('Удаление [] НЕ выполнено.', $d->{name_full}));
    $d->o_postdel();
    my $made_msg = $d->{del_made_msg} || L('Удаление [] выполнено', $d->{name_full});
    $d->{url}->redirect(op=>'list', -made=>$made_msg);
}

1;
