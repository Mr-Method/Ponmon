#<ACTION> file=>'web/ajOnuGraph.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor ONU graph
# NoDeny revision: 715
# Updated date: 2025.08.20
# ------------------------------------------------------------
use strict;
use Time::localtime;

sub go {
    my $domid = ses::input('domid');
    push @$ses::cmd, {
        id   => 'a_onu_graph',
        data => _proc_onu_list($_[0]),
    };
}

sub _proc_onu_list {
    my ($Url) = @_;
    my $onu = ses::input_int('bid');
    my $time = ses::input_exists('tm_stat') ? ses::input_int('tm_stat') : $ses::t;
    my $title = the_date($time);
    my $_tbl_name_template = 'z%d_%02d_%02d_pon';

    my $t = localtime($time);
    my ($day_now, $mon_now, $year_now) = ($t->mday, $t->mon, $t->year);
    my $pon_tbl_name = sprintf $_tbl_name_template, $year_now+1900, $mon_now+1, $day_now;
    debug $pon_tbl_name;

    my $pointsrx = [];
    my $pointstx = [];
    my $series = [];
    my $min_y = 0;

    Db->do("DELETE FROM $pon_tbl_name WHERE `rx` IS NULL AND `rx` IS NULL");
    my $db = Db->sql("SELECT * FROM $pon_tbl_name WHERE bid=? ORDER BY time ASC", $onu);
    my ($rx, $tx) = 0;
    while (my %p = $db->line) {
        #next if $p{rx} eq '';
        #next if $p{tx} eq '';
        $rx = $p{rx} if $p{rx} ne '';
        $tx = $p{tx} if $p{tx} ne '';
        #$rx = $p{rx} ? $p{rx} : $rx;
        #$tx = $p{tx} ? $p{tx} : $tx;

        push @$pointsrx, { x=>$p{time}*1000, y=>$rx };
        push @$pointstx, { x=>$p{time}*1000, y=>$tx };
        $min_y = $p{rx} if $p{rx} < $min_y;
        $rx = $p{rx};
        $tx = $p{tx};
    }

    push @$series, {
        points => $pointstx,
        name   => 'TX',
        color  => 'red',
        num    => int(scalar @$series)
    };

    push @$series, {
        points => $pointsrx,
        name   => 'RX',
        color  => 'blue',
        num    => int(scalar @$series)
    };

    return 'Not found' if !scalar @$series;
    return render_template(
        'onu_graph',
        locale  => $cfg::Lang,
        title   => $title,
        x_title => $lang::lbl_time,
        y_title => 'dBi',
        series  => $series
    );
}

1;
