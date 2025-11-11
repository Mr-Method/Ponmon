#<ACTION> file=>'web/ponmon.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor web interface
# NoDeny: rev. 718
# Update: 2025.11.01
# ------------------------------------------------------------
use strict;
use Debug;

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

my $super_priv = Adm->chk_privil('SuperAdmin') && $ses::auth->{trust};

sub go {
    my ($Url) = @_;
    Doc->template('top_block')->{title} = 'PON monitor';
    my %subs = (
        list => 1,
        edit => 1,
        del  => 1,
    );

    my $act = ses::input('act') || 'list';
    $act = 'list' if !$subs{$act};
    $Url->{act} = $act;
    my $menu = '';
    my @ols_list;
    my $db = Db->sql('SELECT o.*, (SELECT COUNT(*) FROM pon_bind WHERE olt_id = o.id) AS binds FROM pon_olt o ORDER BY o.id ASC');
    my $counto = 0;
    while (my %p = $db->line) {
        $pon{olt}{$p{id}}=\%p;
        $menu .= $Url->a("$p{name} ($p{vendor}-$p{model}): $p{binds}", act=>'list', olt=>$p{id});
        $counto += $p{binds};
        push @ols_list, $p{id}, "$p{name} ($p{vendor}-$p{model}): $p{binds}";
    }
    unshift @ols_list, 0, "Всі OLT: $counto";
    $menu = $Url->a("Всі OLT: $counto", act=>'list', olt=>0)."<hr>" .$menu;
    my $olt=ses::input_int('olt') || 0;

    Doc->template('top_block')->{title} = _('PON monitor:: OLT: [bold]', $pon{olt}{$olt}{name}) if $olt;

    my @form;
    push @form, _('[]', '&nbsp;'.v::select(name => 'olt',     options => \@ols_list, selected => $olt, onchange=>"this.form.submit()").'&nbsp;');
    push @form, _('[]', '&nbsp;'.v::input_t(name => 'sn',     size => 20, value => ses::input('sn'),     placeholder => L('Серійний номер'), autofocus=>'autofocus').'&nbsp;');
    push @form, _('[]', '&nbsp;'.v::input_t(name => 'branch', size => 10, value => ses::input('branch'), placeholder => L('Гілка')).'&nbsp;');
    push @form, _('[]', '&nbsp;'.v::submit('Пошук'));
    my $search_form = $Url->form(act=>'list', -method => 'get', join '', @form);

    my @menu;
    {
        $super_priv or last;
        push @menu, $Url->a(L('Налаштування OLT'), act=>'pon_olt', a=>'op');

#<HOOK>top_menu

    }
    my $top_menu = _('[div nav]', join '', @menu);

    Doc->template('base')->{top_lines} .= _('[style]', '#content_block{display: flex;justify-content: space-between}#main_block{padding: 5px 2px;flex-grow: 1;align-self: stretch;width: auto}#right_block,#left_block{padding: 0 10px;width: auto;max-width: clamp(250px, 30vw, 400px);word-wrap: break-word}@media screen and (max-width: 700px){#content_block{flex-direction: column}#main_block{order: 1;width: auto}#left_block,#right_block{width: auto;max-width: unset}}');
    Doc->template('base')->{top_lines} .= _('[div top_msg]', _('[div style=display:flex;justify-content:space-between;]', $search_form . $top_menu));
    # Show _('[style]', '.blur_text{filter: blur(2px);text-shadow: 0 0 4px rgba(0, 0, 0, 1.5);color: transparent}'); # for screenshots

    $main::{'pon_'.$act}->($Url, $act);
}

# =====================================
#    Список
# =====================================
sub pon_list {
    my ($Url, $act) = @_;
    Doc->template('top_block')->{title} = 'PON monitor::LIST';

    my $sql   = ['SELECT * FROM pon_bind WHERE 1 '];
    my $sqlcc = ['SELECT COUNT(*) AS cc, `status` FROM `pon_bind` WHERE 1 '];

    my $olt=ses::input_int('olt') || 0;

    if ($olt) {
        $sql->[0] .= " AND olt_id=?";
        $sqlcc->[0] .= " AND olt_id=?";
        push @$sql, $olt;
        push @$sqlcc, $olt;
        $Url->{olt} = $olt;
        Doc->template('top_block')->{title} = _('PON monitor::LIST OLT: [bold]', $pon{olt}{$olt}{name});
    }

    if (defined ses::input('sn') && ses::input('sn') ne '') {
        my $sn = Db->filtr(uc(ses::input('sn')));
        my $mac = $sn;
        $mac =~ s/[-:\.]//g;
        $mac =~ s/(..)(?=.)/$1:/g;
        $sql->[0] .= " AND (sn LIKE '%".$sn."%' OR sn LIKE '%".$mac."%')";
        $Url->{sn} = $sn;
    }

    if (defined ses::input('branch') && ses::input('branch') ne '') {
        my $branch = Db->filtr(lc(ses::input('branch')));
        $sql->[0] .= " AND name LIKE '%".$branch."%'";
        $Url->{branch} = $branch;
    }

    my %orders = (
        'rx'      => { title => L('RX') },
        'tx'      => { title => L('TX') },
        'sn'      => { title => L('Серійний номер') },
        'status'  => { title => L('Статус') },
        'name'    => { title => L('Гілка') },
        'changed' => { title => L('Оновлено') },
    );

    my $order = ses::input('order');
    my $order_up = ses::input_int('order_up');
    $order = $orders{$order} ? $order : 'id';
    $Url->{order} = $order;
    $Url->{order_up} = $order_up;

    $sql->[0] .= ' ORDER BY '.$order;
    $sql->[0] .= $order_up ? ' ASC':' DESC';

    my ($sql, $page_buttons, $rows, $db) = main::Show_navigate_list($sql, ses::input_int('start'), 50, $Url);

    if ($rows < 1) {
        Show main::Box(msg=>L('По фільтру нічого не знайдено'), css_class=>'big bigpadding');
        return;
    } else {
        Doc->template('top_block')->{add_info} .= L('найдено: []', $rows);
    }

    my $tbl = tbl->new(-class=>'td_wide pretty width100', -head=>'head');

    foreach my $ord (keys %orders) {
        my $title = $orders{$ord}{title};
        $title .= $order_up ? ' &uarr;' : ' &darr;' if $order eq $ord;
        $orders{$ord}{header} = [ $Url->a([$title], order=>$ord, order_up=>!$order_up) ];
    }

    while (my %p = $db->line) {
        my ($s, $t, $v) = split /\:/, $p{status};
        $tbl->add($v ? '*' : 'rowoff', [
            [ 'h_center', L('Info'),                [ $Url->a('INFO', act=>'edit', bid=>$p{id}, -class=>'nav') ] ],
            [ '',         L('OLT'),                 $pon{olt}{$p{olt_id}}{name} ],
            [ '',         $orders{name}{header},    $p{name} ],
            [ '',         $orders{sn}{header},      $p{sn} ],
            [ '',         $orders{rx}{header},      $p{rx} ],
            [ '',         $orders{tx}{header},      $p{tx} ],
            [ '',         $orders{status}{header},  "$t($s)" ],
            [ '',         $orders{changed}{header}, the_time($p{changed}) ],
#            [ 'h_center', '', [ $ses::debug && $Url->a('del', act=>'del', bid=>$p{id}) ] ],

#<HOOK>list_buttons

        ]);
    }

    Show $page_buttons.$tbl->show.$page_buttons;

    {
        my @param = ();
        $sqlcc->[0] .= ' GROUP BY `status` ORDER BY `status`';
        if (ref $sqlcc) {
             @param = @$sqlcc;
             $sql = shift @param;
        }

        my $counters = Db->sql(shift @$sqlcc, @$sqlcc);
        my $tblcc = tbl->new(-class=>'td_wide pretty');
        $tblcc->add('head', 'll', L('Статус'), L('Кількість'));
        while (my %p = $counters->line) {
            my ($s, $t, $v) = split /\:/, $p{status};
            my $tbl = tbl->new(-class=>'td_wide pretty');
            debug "$t $p{cc}";
            $tblcc->add('*', 'll', $t, $p{cc});
        }
        ToLeft Menu($tblcc->show());
    }
}

sub pon_edit {
    my ($Url, $act) = @_;
    my $url = $Url;

    my ($domid, $domid_uinfo) = (v::get_uniq_id(), v::get_uniq_id());
    my $fields = Data::fields->new(0, ['d'], { _adr_place => 1 });
    my @buttons = ();
    my $user_field = Set_usr_field_line();

    my $Ftm_stat = ses::input_int('tm_stat') || $ses::t;
    $Ftm_stat = $ses::t if $Ftm_stat > 1956513600; # не больше 2032г. - мало ли как mysql поведет себя...
    $url->{tm_stat} = $Ftm_stat if ses::input_exists('tm_stat');
    $url->{bid} = ses::input_int('bid') if ses::input_exists('bid');

    my %p = Db->line("SELECT * FROM `pon_bind` WHERE id=?", ses::input('bid'));
    my $domid2 = v::get_uniq_id();
    my ($s, $t, $v) = split /\:/, $p{status};
    my $tblc = tbl->new(-class=>'td_wide pretty');
    $tblc->add($v ? '*' : 'rowoff', [
        [ '', L('Гілка'),    $p{name} ],
        [ '', L('SN'),       $p{sn} ],
        [ '', L('RX'),       $p{rx} ],
        [ '', L('TX'),       $p{tx} ],
        [ '', L('Статус'),   "$t($s)" ],
        [ '', L('Оновлено'), the_time($p{changed}) ],
    ]);
    debug('pre', \%p);

    Doc->template('top_block')->{title} = _('PON Monitor::SHOW OLT: [bold]: ONU: [bold]', $pon{olt}{$p{olt_id}}{name}, $p{sn}) if $p{id};

    my $graf_dates = Get_list_of_stat_days('Z', $url, $Ftm_stat, $p{sn});
    Doc->template('base')->{document_ready} .= "\$.getScript('".$cfg::img_dir."/custom/highcharts.12.js')"  if $graf_dates;
    Doc->template('base')->{top_lines} .= WideBox(
        title => L('Графіки'),
        msg => _("[][div id=a_onu_graph style='wide:auto;max-width:90vw']", $graf_dates, ''),
    ) if $graf_dates;

    Show WideBox(msg=>$tblc->show.v::tag('div', id=>'a_onu_info', -body=>''), title=>L('BIND info'));

    if ($url->{bid}) {
        Require_web_mod('ajOnuMenu');
        my @menu = @{act_onu_menu($Url, $url->{bid})};
        ToRight Box(wide=>1, css_class=>'navmenu', msg=>join('', @menu), title=>L('ONU меню')) if scalar @menu;
    }

    if ($url->{bid} && int($cfg::ponmon_web_binds_block)) {
        Require_web_mod('ajOnuPlace');
        my $domid = v::get_uniq_id();
        ToLeft _("[div id=$domid]", _proc_onu_place($Url, $p{sn}, $domid));
    }

    if ($url->{bid}) { # ponmon_onu_info_block
        my $domid = v::get_uniq_id();
        my $reload_url = url->new(a=>'ajOnuInfo', bid=>$url->{bid}, '-data-domid'=>$domid, -ajax=>1);
        ToLeft _("[div id=$domid]", $reload_url->a('wait...', '-data-autosubmit'=>50));
    }

    if ($p{olt_id} && $p{llid}) {
        my $domid = v::get_uniq_id();
        my $reload_url = url->new(a=>'ajOnuFdb', olt_id=>$p{olt_id}, llid=>$p{llid}, '-data-domid'=>$domid, -ajax=>1);
        Show _("[div id=$domid]", $reload_url->a('', '-data-autosubmit'=>50));
    }
}

sub pon_del {
    my ($Url, $act) = @_;
    my $url = $Url;
    $url->{bid} = ses::input_int('bid') if ses::input_exists('bid');
    my $db = Db->do("DELETE FROM `pon_bind` WHERE `id` = ?", $url->{bid});
    return;
}

sub Get_list_of_stat_days {
    my ($tbl_type, $url, $sel_time, $sn) = @_;

    my $DB;
    if ($cfg::ponmon_db_name) {
        my $timeout = $cfg::ponmon_db_timeout || 10;
        my $db = Db->new(
            host    => $cfg::ponmon_db_host,
            user    => $cfg::ponmon_db_login,
            pass    => $cfg::ponmon_db_password,
            db      => $cfg::ponmon_db_name,
            timeout => $timeout,
            tries   => 2,
            global  => 0,
            pool    => [],
        );
        $db->connect;
        $DB = $db if $db->is_connected;
    }
    $DB = Db->self unless $DB;

    my $dbh = $DB->dbh;
    my $sth = $dbh->prepare('SHOW TABLES');
    $sth->execute or return '';
    my $t = localtime(int $sel_time);
    # строка для сравнения с днем, который необходимо выделить
    $sel_time = $t->mday.'.'.$t->mon.'.'.$t->year;
    debug("SHOW TABLES (Таблиц: ".$sth->rows.")");
    my %days;
    while (my $p = $sth->fetchrow_arrayref) {
        $p->[0] =~ /^z(\d\d\d\d)_(\d+)_(\d+)_pon$/i or next;
        my $time = timelocal(59,59,23,$3,$2-1,$1); # конец дня
        $days{$time} = substr('0'.$3,-2,2).'.'.substr('0'.$2,-2,2).'.'.$1;
    }
    my $list_of_days = '';
    my $t1 = 0;
    my $t2 = 0;
    my %dates = ();
    my $i = 1;
    foreach my $time (sort {$b <=> $a} keys %days) {
        my $t = localtime($time);
        my $day  = $t->mday;
        my $mon  = $t->mon;
        my $year = $t->year;
        if ($t1 != $mon || $t2 != $year) {
            $t1 = $mon;
            $t2 = $year;
            $i++;
            $dates{$i}{month} = $lang::month_names[$mon+1].' '.($year+1900).':';
        }
        $dates{$i}{days} .= url->a($day, a=>'ajOnuGraph', sn=>$sn, tm_stat=>$time, -ajax=>1).'&nbsp;';
    }
    foreach my $month (sort keys %dates) {
        $list_of_days .= _('[dt]', $dates{$month}{month} ."\t". $dates{$month}{days});
    }
    return keys %days ? _('[dl]', $list_of_days) : '';
}

#<HOOK>subs


1;
