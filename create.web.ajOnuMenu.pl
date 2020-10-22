#<ACTION> file=>'web/ajOnuMenu.pl',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
use strict;

sub go
{
    my $domid = ses::input('domid');
    ajSmall_window($domid, _proc($_[0], $domid));
}

sub _proc
{
    my($Url, $domid) = @_;
    my $bid = ses::input_int('bid');
    my %p = Db->line('SELECT b.*, olt.vendor, olt.mng_tmpl, olt.ip, olt.name, olt.pon_type '.
        'FROM `pon_bind` b LEFT JOIN pon_olt olt ON (b.olt_id=olt.id) WHERE b.id=?', $bid );

    Db->ok or return $lang::err_try_again;
    %p or return L('ONU с bid=[] не найден', $bid);
    debug('pre', \%p);

    my $admin = Adm->chk_privil('SuperAdmin') || Adm->chk_privil('Admin') || Adm->chk_privil(1204);
    $admin or return $lang::err_no_priv;
    my $ajax_url = $Url->new(bid=>$bid, domid=>$domid, -ajax=>1);

    my $act = ses::input('act');

    if( $act eq 'menu' )
    {
        my $menuTitle = "<h3>Тут поки що немає нічого цікавого :)</h3>";
        my $buttons = '';
        $buttons .= _('[p]', $ajax_url->a(L('Clear FDB cache'), act=>'clearFdb') ) if Adm->chk_privil(1204);

#<HOOK>menu

        return Show _('[div]', $buttons);
    }
    $main::{'act_'.$act}->(\%p);
}

sub _document
{
    my $mng_tmpl = shift;
    my %settings = ();
    return \%settings if !$mng_tmpl;
    my %p = Db->line('SELECT document FROM documents WHERE id=? AND is_section=0', $mng_tmpl );
    %p or return \%settings;
    $p{document} =~ s/\r//gm;
    foreach my $line( split /\n/, $p{document} ) {
        chomp($line);
        $line =~ /([^=\s]+)\s*=\s*(.+)/ or next;
        $settings{$1} = $2;
    }
    chomp(%settings);
#    debug( 'pre', \%settings);
    return \%settings;
}

sub act_clearFdb
{
    my $attr = shift;
    debug('pre', $attr);
    Db->do("DELETE from pon_fdb WHERE llid=? AND olt_id=?", $attr->{llid}, $attr->{olt_id});
    return "Видалено ".Db->rows." записів";
}

#### Battons handlers ####

#<HOOK>subs


#### Battons handlers  END ####

1;
