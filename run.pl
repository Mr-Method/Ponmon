(my $module_dir = __FILE__) =~ s{/+run\.pl$}{};

{
    $cfg::dir_home or die 'where is nodeny dir?';
    my $dir = "$cfg::dir_home/nod/Pon";
    if (! -d $dir) {
        debug "mkdir $dir";
        mkdir $dir, 0777;
        chmod 0777, $dir;
    }

    system("cp -r $module_dir/htdocs/* $cfg::dir_home/htdocs/");
}

Db->is_connected or Db->connect;
{
    my $del_sql = "DELETE FROM pon_bind WHERE sn='__NODENY__TEST__' AND olt_id=-1 AND llid=''";
    Db->do($del_sql);
    Db->do("INSERT INTO pon_bind SET sn='__NODENY__TEST__', status=0, olt_id=-1, llid=''");
    my $id = Db::result->insertid;
    $id or last;
    if (Db->line("SELECT 1 FROM pon_mon WHERE bid=?", $id)) {
        push @warnings::messages, <<MSG
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

You need to remove triggers tr_aft_ins_pon, tr_aft_upd_pon and TABLE pon_mon!
Execute in mysql via root user:

USE nodeny;
DROP TRIGGER IF EXISTS `tr_aft_ins_pon`
DROP TRIGGER IF EXISTS `tr_aft_upd_pon`;
DROP TABLE IF EXISTS `pon_mon`;

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
MSG
    }

    Db->do($del_sql);
}

1;
