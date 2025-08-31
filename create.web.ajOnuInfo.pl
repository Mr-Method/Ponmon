#<ACTION> file=>'web/ajOnuInfo.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny Next (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor ONU info
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
use strict;

sub go {
    my $domid = ses::input('domid');
    my $act = ses::input('act') || 'show';
    if ($act eq 'show') {
        push @$ses::cmd, {
            id => $domid,
            data => act_show($_[0], ses::input('bid'), $domid),
        };
    } else {
        ajSmall_window($domid, $main::{'act_'.$act}->($_[0], ses::input('bid'), $domid));
    }
}

sub _proc_onu_info {
    $main::{'act_show'}->(@_);
}

sub act_show {
    my ($Url, $bid, $domid) = @_;
    my $title = url->a(L('ONU Info'), a=>'ajOnuInfo', bid=>$bid, act=>'show', domid=>$domid, -ajax=>1);
    my %bind = Db->line("SELECT * FROM `pon_bind` WHERE `id`=?", $bid);
    my $sn = $bind{sn};
    my %onu = Db->line("SELECT * FROM `pon_onu` WHERE `sn`=?", $sn);

    my $tbl = tbl->new(-class => 'td_ok fade_border', -style => 'margin: 5px auto');
    # debug 'pre', \%bind;
    if ($bind{olt_id}) {
        my %p = Db->line('SELECT * FROM `pon_olt` WHERE `id`=? AND `enable`>0;', $bind{olt_id});
        $p{cfg} = Debug->do_eval($p{param}) || {};
        my $module = ucfirst(lc($p{vendor}));
        # debug 'error', $module;
        if (my $err = _load_module($module)) {
            tolog("ERROR: OLT id $p{id} ===>\t $err");
            return;
        }
        my $pkg = "nod::Pon::$module";
        return if !$pkg->can('new');
        $p{bind} = {%bind};
        # next if !$pkg->can('unregistered');
        my $olt = $pkg->new({%p});
        if ($olt->can('onu_info')) {
            # debug 'pre', $olt;
            my $data = $olt->onu_info();
            # debug 'pre', $data;
            foreach my $key (sort keys %$data) {
                my $value = $data->{$key};
                $value =~ s/^\s*\"|\s*\"$//mg;
                $tbl->add('*', 'll', [L($key)], [$value]);
            }
        }
    }
    return $tbl->rows ? WideBox(msg => $tbl->show, title => $title) : '';
}

sub _load_module {
    my $name = shift;
    $name = ucfirst(lc($name));
    debug "$cfg::dir_home/nod/Pon/$name.pm";
    eval { require "$cfg::dir_home/nod/Pon/_$name.pm" };
    my $err = "$@";
    debug 'error', $err if $err && -e "$cfg::dir_home/nod/Pon/_$name.pm";
    $err && eval { require "$cfg::dir_home/nod/Pon/$name.pm" };
    return "$@";
}

1;
