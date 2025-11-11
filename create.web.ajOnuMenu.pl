#<ACTION> file=>'web/ajOnuMenu.pl',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: ONU Menu
# NoDeny: rev. 718
# Update: 2025.11.01
# ------------------------------------------------------------
use strict;

my @cmd_list = ();
my $ajax_url;

my $debug = 0;
my $domid;

sub go {
    $domid = ses::input('domid');
    ajSmall_window($domid, _proc($_[0]));
    debug('pre', \@cmd_list) if scalar @cmd_list;
}

sub _proc {
    my ($Url) = @_;

    my $bid = ses::input_int('bid');
    my $admin = Adm->chk_privil('SuperAdmin') || Adm->chk_privil('Admin') || Adm->chk_privil(1204);
    $admin or return $lang::err_no_priv;
    my %p = Db->line(
        'SELECT b.*, olt.vendor, olt.ip, olt.name AS olt_name, olt.pon_type, olt.param, olt.model '.
        'FROM `pon_bind` b LEFT JOIN pon_olt olt ON (b.olt_id=olt.id) WHERE b.id=?', $bid
    );
    Db->ok or return $lang::err_try_again;
    %p or return L('ONU с bid=[] не найден', $bid);
    $p{cfg} = Debug->do_eval($p{param});
    delete $p{param};
    debug('pre', \%p);
    $ajax_url = $Url->new(bid=>$bid, domid=>$domid, -ajax=>1);
    return L('No defined OLT param') if ref $p{cfg} ne 'HASH' ;

    my $act = ses::input('act');
    $main::{'act_'.$act}->(\%p) || "";
}

sub act_onu_menu {
    my ($Url, $bid) = @_;
    my @menuItems = ();

    my %p = Db->line(
        'SELECT b.*, olt.vendor, olt.ip, olt.name AS olt_name, olt.pon_type, olt.param, olt.model '.
        'FROM `pon_bind` b LEFT JOIN pon_olt olt ON (b.olt_id=olt.id) WHERE b.id=?', $bid
    );
    Db->ok or return \@menuItems;
    $p{cfg} = Debug->do_eval($p{param});
    debug('pre', \%p);
    delete $p{param};
    return \@menuItems if ref $p{cfg} ne 'HASH';

    if (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1201)) { # allow macs view

#<HOOK>menu_macs

    }
    if (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1202)) { # allow bind view

#<HOOK>menu_bind

    }
    if (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1203)) { # allow onu reboot

#<HOOK>menu_reboot

    }
    if (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1204)) { # allow onu settings

#<HOOK>menu_settings

    }
    if (Adm->chk_privil('SuperAdmin') || Adm->chk_privil(1205)) { # allow olt terminal

#<HOOK>menu_terminal

    }
    if (Adm->chk_privil('SuperAdmin')) {

#<HOOK>menu_super

    }

#<HOOK>menu

    my @menu = ();
    my $ajax_url = $Url->new(a=>'ajOnuMenu', bid=>$bid, '-data-ajax-into-here'=>1);
    foreach my $item (sort { $a->{order} <=> $b->{order} } @menuItems) {
        my $domid = v::get_uniq_id();
        my $link = $ajax_url->a($item->{title}, act=>$item->{act}, exists $item->{param} && map { $_ => $item->{param}{$_}, } keys %{$item->{param}}, '-data-ajax-into-here'=>1);
        push @menu, _("[div id=$domid]", $link);
    }
    debug 'pre', \@menu;
    return \@menu;
}

# sub act_test {
#     my $attr = shift;
#     debug('pre', $attr);
#     my $form = _('[p][p][p]', L('Enter vlan id'), v::tag('input', type=>'number', name=>'vlan', value=>'0', size=>16, min=>1, max=>4095, 'required'), v::submit($lang::btn_Execute));
#     return $ajax_url->form(-class=>'ajax', act=>'test', -method=>'post', $form) unless (ses::input_int('vlan'));
#     return $ajax_url->a($lang::btn_Execute, act=>'test', go=>1) unless ses::input_int('go');
#     return "Видалено 100500 записів";
# }

sub _load_module {
    my $name = shift;
    $name = ucfirst(lc($name));
    debug "$cfg::dir_home/nod/Pon/$name.pm";
    eval{ require "$cfg::dir_home/nod/Pon/_$name.pm" };
    my $err = "$@";
    debug 'error', $err if $err && -e "$cfg::dir_home/nod/Pon/_$name.pm";
    $err && eval{ require "$cfg::dir_home/nod/Pon/$name.pm" };
    return "$@";
}

sub _telnetConnect {
    my $attr = shift;
    my $module = ucfirst(lc($attr->{vendor}));
    if (my $err = _load_module($module)) {
        tolog("ERROR: OLT id $attr->{id} ===>\t $err");
        exit;
    }
    my $pkg = "nod::Pon::$module";
    my $olt = $pkg->new($attr);
    my $tnc = $olt->telnet_connect();
    $tnc->input_log(*STDOUT)  if $debug;
    $tnc->output_log(*STDOUT) if $debug;
    return $tnc;
}

sub _telnetClose {
    my $tc = shift;
    no warnings;
    eval {
        $tc->close();
        $tc->shutdown(2) if $tc;
        undef $tc;
    };
}

sub _tnCmd {
    my ($tc, $cmd) = @_;
    my $pt = $tc->last_prompt();
    $pt =~ s/^\s*|\s*$//mg;
    my @output = ();
    if (ref $cmd eq "HASH") {
        $cmd->{Output} = \@output;
        $tc->cmd(%$cmd)
    } else {
        $tc->cmd(String => $cmd, Output => \@output);
    }
    push @cmd_list, $pt.' '.$tc->last_cmd;
    return (@output);
}

sub _tnError {
    my ($tc, $msg) = @_;
    _telnetClose($tc);
    return ($msg);
}

#### Battons handlers ####

#<HOOK>subs


#### Battons handlers  END ####

1;
