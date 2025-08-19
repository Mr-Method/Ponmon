#<ACTION> file=>'web/user.pl',hook=>'ponmon_info'

    if (Adm->chk_privil(1201)) {
        Require_web_mod('ajUserOnu');
        my $domid = v::get_uniq_id();
        push @left, _("[div id=$domid]", _proc_user_onu($Url, $Fuid, $domid)) . $Url->a('', a=>'ajUserOnu', uid=>$Fuid, '-data-domid'=>$domid, -ajax=>1);
    }
