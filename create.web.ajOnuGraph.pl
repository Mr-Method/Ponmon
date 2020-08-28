#<ACTION> file=>'web/ajOnuGraph.pl',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
use strict;
use Time::localtime;

sub go
{
    my $domid = ses::input('domid');
    push @$ses::cmd, {
        id   => 'a_onu_graph',
        data => _proc_onu_list($_[0], ses::input_int('bid'), $domid),
    };
}

sub _proc_onu_list
{
    my($Url) = @_;
    my $onu = ses::input_int('bid');
    my $time = ses::input_exists('tm_stat') ? ses::input_int('tm_stat') : $ses::t;
    my $title = the_date($time);
    my $_tbl_name_template = 'z%d_%02d_%02d_pon';

    my $t = localtime($time);
    my ($day_now, $mon_now, $year_now) = ($t->mday, $t->mon, $t->year);
    my $pon_tbl_name = sprintf $_tbl_name_template, $year_now+1900, $mon_now+1, $day_now;
    debug $pon_tbl_name, "\n";

    my $graph_rough = ses::input_exists('graph_rough')? ses::input_int('graph_rough') : int $ses::cookie->{graph_rough};
    # Сколько срезов группировать в один
    my $graph_rough_lvl = 2 ** $graph_rough;
    my $period = 4*60;
    my $half_period = int($period/2);

    my $pointsrx = [];
    my $pointstx = [];
    my $series = [];
    my $min_y = 0;

    my $db = Db->sql("SELECT * FROM $pon_tbl_name WHERE bid=? ORDER BY time ASC", $onu );
    my ($rx, $tx) = 0;
    while( my %p = $db->line )
    {
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
        points=>$pointstx,
        name=>'TX',
        color=>'red',
        num=>int(scalar @$series)
    };

    push @$series, {
        points=>$pointsrx,
        name=>'RX',
        color=>'blue',
        num=>int(scalar @$series)
    };

    debug 'pre', $series;

    return render_template('onu_graph',
        title   => $title,
        y_title => 'dBi',
        series  => $series,
        rough   => $graph_rough,
    );
}

1;
