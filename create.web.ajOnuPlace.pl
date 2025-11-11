#<ACTION> file=>'web/ajOnuPlace.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor ONU place management
# NoDeny: rev. 718
# Update: 2025.11.01
# ------------------------------------------------------------
use strict;

my %place_type_list = (
    'user' => 'В абонента',
    'map' => 'На ТКД',
);

sub go {
    my $domid = ses::input('domid');
    my $act = ses::input('act') || 'show';
    if ($act eq 'show') {
        push @$ses::cmd, {
            id => $domid,
            data => act_show($_[0], ses::input('sn'), $domid),
        };
    } else {
        ajSmall_window($domid, $main::{'act_'.$act}->($_[0], ses::input('sn'), $domid));
    }
}

sub _proc_onu_place {
    $main::{'act_show'}->(@_);
}

sub act_show {
    my ($Url, $sn, $domid) = @_;
    my $title = url->a(L('Розташування'), a=>'ajOnuPlace', sn=>$sn, act=>'show', domid=>$domid, -ajax=>1);
    my %onu = Db->line("SELECT * FROM `pon_onu` WHERE `sn`=?", $sn);
    my $tbl = tbl->new(-class => 'td_ok fade_border', -style => 'margin: 5px auto');
    if ($onu{place_type} eq 'map' && !!$onu{place}) {
        $tbl->add('*', 'lc', ['Тип розміщення: '], [$place_type_list{$onu{place_type}}]);
        my $place = Get_place_name_by_id($onu{place}) || 'Не вибрано';
        $tbl->add('*', 'L', [ _('[span style=color:forestgreen;]', $place) ]);
    } elsif ($onu{place_type} eq 'user' && $onu{place} > 0) {
        $tbl->add('*', 'lc', ['Тип розміщення: '], [$place_type_list{$onu{place_type}}]);
        my $domid2 = v::get_uniq_id();
        my $domid_uinfo = v::get_uniq_id();
        my $place = _('[span style=color:goldenrod;]', v::tag('input', type => 'hidden', value => ($onu{place} ? $onu{place} : ''), id => $domid2, 'data-autoshow-userinfo' => $domid_uinfo).v::tag('div', id => $domid_uinfo));
        $tbl->add('*', 'L', [ _('[span style=color:forestgreen;]', $place) ]);
    } elsif ($cfg::ponmon_web_user_sn_field ne '') {
        my %data0 = Db->line("SELECT uid FROM `data0` WHERE ".Db->filtr($cfg::ponmon_web_user_sn_field)."=?", $sn);
        if (defined $data0{uid} && $data0{uid} > 0) {
            $tbl->add('*', 'lc', ['Тип розміщення: '], [$cfg::ponmon_web_user_sn_field]);
            my $domid2 = v::get_uniq_id();
            my $domid_uinfo = v::get_uniq_id();
            my $place = _('[span style=color:goldenrod;]', v::tag('input', type => 'hidden', value => $data0{uid}, id => $domid2, 'data-autoshow-userinfo' => $domid_uinfo).v::tag('div', id => $domid_uinfo));
            $tbl->add('*', 'L', [ _('[span style=color:forestgreen;]', $place) ]);
        }
    } else {
        $tbl->add('*', 'lc', ['Тип розміщення: '], [_('[span style=color:red;]', 'Не вибрано')]);
    }
    if (int($cfg::ponmon_web_manual_bind)) {
        $tbl->add('*','C', [url->a(L('Змінити'), a=>'ajOnuPlace', sn=>$sn, act=>'change', '-data-ajax-into-here'=>1)]);
    }
    return WideBox(msg => $tbl->show, title => $title);
}

sub act_change {
    my ($Url, $sn, $domid) = @_;
    my %onu = Db->line("SELECT * FROM `pon_onu` WHERE `sn`=?", $sn);
    my @buttons = ();
    my $ajax_url = $Url->new(domid=>$domid, sn=>$sn, -ajax=>1);
    push @buttons, _('[p]', $ajax_url->a(L('Вибрати абонента'), act=>'set_user'));
    push @buttons, _('[p]', $ajax_url->a(L('Вибрати точку топології'), act=>'set_place')) if !!$cfg::ponmon_web_places_object;
    push @buttons, _('[p]', $ajax_url->a(L("Відв'язати"), act=>'save', update=>'clear')) if $onu{place} && $onu{place} > 0;
    return Show _('[div]', join '', map { $_ } @buttons);
}

sub act_set_user {
    my ($Url, $sn, $domid) = @_;
    my $tbl = tbl->new(-class=>'td_wide td_medium');
    my $domid2 = v::get_uniq_id();
    my $domid_uinfo = v::get_uniq_id();
    $tbl->add('', 'ccc',
        [$Url->a(['Вибрати абонента'], a => 'user_select', force => 1, -separator => '&', -class => 'new_window nav_button', '-data-parent' => $domid2)],
        [v::tag('input', type => 'hidden', name => 'set_user', id => $domid2, 'data-autoshow-userinfo' => $domid_uinfo).v::tag('div', id => $domid_uinfo)],
        [v::submit('Зберегти')]
    );
    return $Url->form(
        a => 'ajOnuPlace', act => 'save', -class => 'ajax', sn => $sn, domid => $domid, update => 'set_user',
        _("[div style=display:flex;justify-content:center;align-items:center;]", _("[div]", $tbl->show))
    );
}

sub act_set_place {
    my ($Url, $sn, $domid) = @_;
    my $Dictionary;
    main::Require_web_mod('Data') && die;
    $Dictionary = Data->dictionary;
    if (my $dict = $Dictionary->{$cfg::ponmon_web_places_object}) {
        my %places = @$dict;
        my @tkds = ();
        #my @positioned = sort { $data->{$a}{Position} <=> $data->{$b}{Position} }  keys %$data;
        for my $key (sort { $places{$a}{v} cmp $places{$b}{v} } keys %places) {
            my $value = $places{$key}{v};
            next if $value =~ /^\s*$/;
            next if !$value;
            push @tkds, $key, $value;
        }
        return Show _('[div]', L('Немає точок топології')) unless @tkds;
        unshift @tkds, '0', L('Вибрати адресу');
        return $Url->form(
            a => 'ajOnuPlace', act => 'save', -class => 'ajax', sn => $sn, domid => $domid, update => 'set_place',
            _("[div style=display:flex;justify-content:center;align-items:center;]",
                _("[div]", v::select(name => 'set_place', options => \@tkds, 'data-autofocus' => 0, class => 'pretty')).'&nbsp;&nbsp;&nbsp;'._('[div]', v::submit('Зберегти'))
            )
        );
    } else {
        return Show _('[div]', L('Не знайдено об`єкт []', $cfg::ponmon_web_places_object));
    }
    #return _("[div style=display:flex;justify-content:center;align-items:center;]", _("[div]", 'Адреса ТКД:').'&nbsp;&nbsp;&nbsp;'._("[div]", v::select(name => 'tkd_id', options => \@tkds, 'data-autofocus' => 0, class => 'pretty')));
}

sub act_save {
    my ($Url, $sn, $domid) = @_;
    my $ajax_url = $Url->new(domid=>$domid, sn=>$sn, -ajax=>1);

    my $update = ses::input('update');
    if ($update eq 'set_user') {
         my $uid = ses::input('set_user');
         my $rows = 0;
         if ($uid > 0) {
             $rows = Db->do("UPDATE `pon_onu` SET `place_type` = 'user', `place` = ? WHERE `sn` = ?", $uid, $sn);
             if (!!$cfg::ponmon_web_user_sn_field && !!$cfg::ponmon_web_user_sn_copy) {
                 Db->do("UPDATE `data` SET ".Db->filtr($cfg::ponmon_web_user_sn_field)." = ? WHERE `sn` = ?", $sn, $uid);
             }
         } else {
             $rows = Db->do("UPDATE `pon_onu` SET `place_type` = NULL, `place` = 0 WHERE `sn` = ?", $sn);
             #ALTER TABLE `pon_onu` CHANGE `place` `place` INT UNSIGNED NOT NULL DEFAULT '0';
         }
         return Show _('[div]', Db->rows > 0 ? L('Оновлено') : L('Помилка'));
    } elsif ($update eq 'set_place') {
         my $tkd = ses::input('set_place');
         my $rows = 0;
         if (!!$tkd) {
             $rows = Db->do("UPDATE `pon_onu` SET `place_type` = 'map', `place` = ? WHERE `sn` = ?", $tkd, $sn);
         } else {
             $rows = Db->do("UPDATE `pon_onu` SET `place_type` = NULL, `place` = 0 WHERE `sn` = ?", $sn);
             #ALTER TABLE `pon_onu` CHANGE `place` `place` INT UNSIGNED NOT NULL DEFAULT '0';
         }
         return Show _('[div]', Db->rows > 0 ? L('Оновлено') : L('Помилка'));
    } elsif ($update eq 'clear') {
         return Show _('[b]', $ajax_url->a(L("Відв'язати?"), act=>'save', update=>'clear_now'));
    } elsif ($update eq 'clear_now') {
         my $rows = Db->do("UPDATE `pon_onu` SET `place_type` = NULL, `place` = 0 WHERE `sn` = ?", $sn);
         return Show _('[div]', Db->rows > 0 ? L('Оновлено') : L('Помилка'));
    } else {
         return Show _('[div]', L('Помилка'));
    }
#    return Show _('[div]', join '', map { $_ } @buttons);
}

sub Get_place_name_by_id {
    my ($place) = @_;
    return $place unless $cfg::ponmon_web_places_object;
    my $Dictionary;
    main::Require_web_mod('Data') && return "Error load Data";
    $Dictionary = Data->dictionary;
    if (defined $Dictionary->{$cfg::ponmon_web_places_object}) {
        my $dict = $Dictionary->{$cfg::ponmon_web_places_object};
        my %places = @$dict;
        return $places{$place}{v} || '';
    } else { return $place }
}

1;
