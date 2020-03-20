#<ACTION> file=>'web/ajOnuGraph.pl',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
use strict;

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

    my $graph_rough = ses::input_exists('graph_rough')? ses::input_int('graph_rough') : int $ses::cookie->{graph_rough};
    # Сколько срезов группировать в один
    my $graph_rough_lvl = 2 ** $graph_rough;
    my $period = 4*60;
    my $half_period = int($period/2);

    my $pointsrx = [];
    my $pointstx = [];
    my $series = [];
    my $min_y = 0;

    my $db = Db->sql("SELECT * FROM pon_mon WHERE bid=? ORDER BY time ASC", $onu );
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

    my @months = ();
    foreach( @lang::month_names[1..12] )
    {
        utf8::decode($_);
        $_ = substr $_, 0, 3;
        utf8::encode($_);
        push @months, _("'[filtr]'", $_);
    }

    return render_template('onu_graph',
        title  => 'title',
        months => join(',', @months),
        series => $series,
        rough  => $graph_rough,
    );
}

1;
