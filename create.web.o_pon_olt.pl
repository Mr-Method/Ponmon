#<ACTION> file=>'web/o_pon_olt.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor OLT management
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
# https://jsfiddle.net/mrMethod/k9paur0q/10
package op;
use strict;
use Debug;

$Data::Dumper::Sortkeys = 1;

my $d = {
    name        => L('Сервери OLT'),
    name_full   => 'OLT',
    table       => 'pon_olt',
    field_id    => 'id',
    priv_show   => 'Admin',
    priv_edit   => 'SuperAdmin',
    priv_copy   => 'SuperAdmin',
    allow_copy  => 1,
    sql_get     => 'SELECT * FROM `pon_olt` WHERE `id`=?',
    menu_create => L('Додати OLT'),
    menu_list   => L('Всі OLT'),
};

my %enable_opt = (
    0 => L('Ні'),
    1 => L('Так'),
    2 => L('Самостійно'),
);

sub o_start {
    Doc->template('top_block')->{title} = $d->{name};
    $cfg::dir_vendors = "$cfg::dir_home/nod/Pon";
    my %Modules = ();
    $d->{_vendors} = \%Modules;

    opendir (my $dh, $cfg::dir_vendors) or Error_Lang(
        'Не могу прочитать каталог: [filtr|p]Если существует - проверьте права доступа.',
        $cfg::dir_vendors
    );

    # В 2 этапа, поскольку нужно исключить основные файлы, если у них есть фантомы
    while (my $module = readdir($dh)) {
        $module =~ s/^_?(.+)\.pm$/$1/ or next;
        $Modules{$module} = {};
    }

    foreach my $module (sort keys %Modules) {
        my $err = main::Require_mod("nod/Pon/$module.pm");
        if ($err) {
            debug 'error', $err;
            next;
        }
        my $pkg  = "nod::Pon::$module";
        my $info = $pkg->can('info') ? $pkg->info() : {};
        debug('pre', $module, $info);
        if (ref $info eq 'HASH' && ref $info->{pon_types} eq 'HASH') {
            $Modules{$module} = { %$info };
        } else {
            delete $Modules{$module};
            next;
        }
    }
    closedir $dh;
    keys %Modules or Error_Lang('Нет ни одного модуля вендора (файла *.pm) в каталоге: [filtr|p]', $cfg::dir_vendors);
    $d->{modules} = \%Modules;
    return $d;
}

sub o_list {
    my ($d) = @_;
    my $url = $d->{url}->new();

    my $sql_where = 'WHERE 1';
    my @sql_param = ();

    my $tbl = tbl->new(-class=>'td_wide pretty', -head=>'head', -row1=>'row3', -row2=>'row3');
    my $db = Db->sql("SELECT * FROM `pon_olt` $sql_where ORDER BY `id`", @sql_param);
    while (my %p = $db->line) {
        $tbl->add($p{enable} ? '*' : 'rowoff', [
            [ 'h_right', 'id', $p{id} ],
            [ '', L('Увімкнено'), $enable_opt{$p{enable}} ],
            [ '', L('Имя'),       $p{name} ],
            [ '', L('Вендор'),    $d->{modules}{$p{vendor}}{name} || $p{vendor} ],
            [ '', L('Тип'),       $d->{modules}{$p{vendor}}{pon_type}{$p{pon_type}} || $p{pon_type} ],
            [ '', L('Model'),     $p{model} ],
            [ '', L('IP Адрес'),  $p{ip} ],
            [ '', L('SNMP порт'), $p{snmp_port} ],
            [ '', '',             $d->btn_edit($p{id}) ],
            [ '', '',             $d->btn_copy($p{id}) ],
        ]);
    }
    Show $tbl->show;
}

sub o_new {
    my ($d) = @_;
    $d->{d}{param} = {};

    $d->{d}{name} //= '';
    $d->{d}{model} //= '';
    $d->{d}{firmware} //= '';
    $d->{d}{ip} //= '';
    $d->{d}{snmp_port} //= 161;
    $d->{d}{enable} //= 2;
}

sub o_edit {
    my ($d) = @_;
    $d->{d}{param} = Debug->do_eval($d->{d}{param});
    if (!$d->{d}{param} || $d->{d}{param} eq '') {
        ToTop L('Внимание. Параметры не расшифрованы т.к. они повреждены');
        $d->{d}{param} = {};
    }
}

sub o_show {
    my ($d) = @_;
    my @menu = ();
    my %params = defined $d->{d}{param} ? %{$d->{d}{param}} : {};

    my $tbl = tbl->new(-class=>'td_wide wide_input');
    my $edit_priv = $d->chk_priv('priv_edit') || 0;
    push @menu, '<br>', url->a('help', a=>'help', theme=>'olt_params') if $edit_priv;

    my @vendorlist = ();
    foreach my $vendor (sort { $d->{modules}{$a}{name} =~ /old/i <=> $d->{modules}{$b}{name} =~ /old/i || $a cmp $b } keys %{$d->{modules}}) {
        foreach my $ptype (sort keys %{$d->{modules}{$vendor}{pon_types}}) {
            push @vendorlist, "$vendor:$ptype", "$d->{modules}{$vendor}{name}:$d->{modules}{$vendor}{pon_types}{$ptype}";
        }
    }

    my $is_enable = exists $enable_opt{$d->{d}{enable}} ? $d->{d}{enable} : 0;
    my $enabled = v::select(
        name     => 'enable',
        size     => 1,
        options  => [map { $_ => $enable_opt{$_} } sort keys %enable_opt],
        selected => $is_enable,
    );

    my $vendor_selected = $d->{d}{vendor} && $d->{d}{pon_type} ? "$d->{d}{vendor}:$d->{d}{pon_type}" : '';
    my $vendors = v::select(
        name     => 'vendor',
        size     => 1,
        options  => \@vendorlist,
        selected => $vendor_selected,
    );

    $tbl->add('', 'll', L('Увімкнено'), [ $enabled ]);
    $tbl->add('', 'll', L('Назва'),     [ v::input_t(name=>'name', value=>$d->{d}{name}) ]);
    $tbl->add('', 'll', L('vendor'),    [ $vendors ]);
    $tbl->add('', 'll', L('model'),     [ v::input_t(name=>'model', value=>$d->{d}{model}) ]);
    $tbl->add('', 'll', L('firmware'),  [ v::input_t(name=>'firmware', value=>$d->{d}{firmware}) ]);

    $tbl->add('', 'll', L('IP'),        [ v::input_t(name=>'ip', value=>$d->{d}{ip}) ]);
    $tbl->add('', 'll', L('SNMP Port'), [ v::input_t(name=>'snmp_port', value=>$d->{d}{snmp_port}) ]) if $edit_priv;

    $tbl->add('', 'C',  [_('[hr]') ]);
    my $help = $edit_priv ? ' | '. url->a('HELP', a=>'help', theme=>'olt_params') : '';
    $tbl->add('', 'C',  [L('Параметри').$help]);
    $tbl->add('', 'cc', L('ключ'), L('значення'));
    foreach my $key (sort keys %params) {
        my $value = $params{$key};
        $value =~ s/^\s*|\s*$//mg;
        $key   =~ s/^\s*|\s*$//mg;
        if (length($params{$key}) > 50) {
            $tbl->add('', 'll', $key.' ', [ v::input_ta('param_'.$key, $value, 40, 4) ]);
        } else {
            if ($key =~ /\+$/) {
                my $name = $key;
                $name =~ s/\+$//gm;
                debug "$name : $value";
                $tbl->add('*', 'll', $name.' ', [ v::input_p(name=>'param_'.$key, value=>$value, size=>43) ]) if $edit_priv;
            } else {
                $tbl->add('*', 'll', $key.' ', [ v::input_t(name=>'param_'.$key, value=>$value) ]);
            }
        }
    }
    $tbl->add('', 'll',[ v::input_t(name=>'param_key0', value=>'', size=>10) ], [ v::input_t(name=>'param_value0', value=>'', size=>20) ]);
    $tbl->add('', 'll',[ v::input_t(name=>'param_key1', value=>'', size=>10) ], [ v::input_t(name=>'param_value1', value=>'', size=>20) ]);
    $tbl->add('', 'll',[ v::input_t(name=>'param_key2', value=>'', size=>10) ], [ v::input_t(name=>'param_value2', value=>'', size=>20) ]);
    $tbl->add('', 'C', [_('[hr]') ]);
    $tbl->add('', 'C', L('Комментар'));
    $tbl->add('', 'C', [ v::input_textarea(name => 'descr', cols => 80, rows => 6, maxlength => 1000, -body => $d->{d}{descr}) ]);

    if ($edit_priv) {
        $tbl->add('','C', [ v::submit($lang::btn_save) ]);
        push @menu, '<br>', $d->{url}->a($lang::btn_delete, op=>'del');
    }

    Show $d->{url}->form(id=>$d->{id}, $tbl->show);
    ToRight _('[div bigpadding navmenu]', join('', @menu));
}

sub o_update {
    my ($d) = @_;
    my %data = %{$ses::input_orig};
    my %param = ();

    $d->{sql} .= 'SET `name`=?, `vendor`=?, `model`=?, `firmware`=?, `ip`=?, `snmp_port`=?, `pon_type`=?, `descr`=?, `enable`=?, `param`=?, `changed`=UNIX_TIMESTAMP()';

    my ($vendor, $ptype) = split /\:/, $data{vendor};
    push @{$d->{param}}, $data{name};
    push @{$d->{param}}, $vendor;
    push @{$d->{param}}, $data{model};
    push @{$d->{param}}, $data{firmware};

    push @{$d->{param}}, $data{ip};
    push @{$d->{param}}, $data{snmp_port} || 161;

    push @{$d->{param}}, $ptype || 'gpon';

    push @{$d->{param}}, v::trim($data{descr});
    push @{$d->{param}}, $data{enable} || 0;

    for my $kk (0..2) {
        my $key = defined $data{'param_key'.$kk} ? delete $data{'param_key'.$kk} : '';
        $key =~ s/\s//gm;
        my $value = defined $data{'param_value'.$kk} ? delete $data{'param_value'.$kk} : '';
        $value =~ s/^\s*|\s*$//gm;
        next if $key eq '' || $value eq '';
        $param{lc($key)} = lc($value);
    }
    foreach my $key (sort keys %data) {
        next unless $key =~ m/^param_/;
        my $name = $key;
        $name =~ s/^param_|\s//gi;
        my $value = $data{$key};
        $value =~ s/^\s*|\s*$//gm;
        $param{lc($name)} = $value if $value;
    }

    my $params = Debug->dump(\%param);
    debug 'pre', $params;
    push @{$d->{param}}, $params;
}

sub o_insert { return o_update(@_); }

sub o_predel {
    my ($d) = @_;
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
        [ "INSERT INTO `changes` SET `act`='delete', `new_data`='', `time`=UNIX_TIMESTAMP(), `tbl`=?, `fid`=?, `adm`=?, `old_data`=?",
            $d->{table}, $d->{id}, Adm->id, Debug->dump($d->{d}) ],
    );
    if ($ok) {
        Db->do("DELETE FROM `pon_bind` WHERE `olt_id`=? ", $d->{id});
        Db->do("DELETE FROM `pon_fdb` WHERE `olt_id`=? ", $d->{id});
    }
    $ok or Error(L('Удаление [] НЕ выполнено.', $d->{name_full}));
    $d->o_postdel();
    my $made_msg = $d->{del_made_msg} || L('Удаление [] выполнено', $d->{name_full});
    $d->{url}->redirect(op=>'list', -made=>$made_msg);
}

1;
