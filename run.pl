{
    $cfg::dir_home or die 'where is nodeny dir?';
    my $dir = "$cfg::dir_home/nod/Pon";
    if( ! -d $dir )
    {
        debug "mkdir $dir";
        mkdir $dir, 0777;
        chmod 0777, $dir;
    }
}

Db->is_connected or Db->connect;
{
    my $st_table = Db->dbh->column_info(undef, undef, 'pon_olt', undef);
    my %cols = ();
    while( my $table_hash = $st_table->fetchrow_hashref() )
    {
        $cols{$table_hash->{COLUMN_NAME}} = 1;
    }
    if( $cols{mng_pswd} )
    {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_pswd`');
        Db->ok or die $cfg::sql_err;
    }
    if( $cols{mng_user} )
    {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_user`');
        Db->ok or die $cfg::sql_err;
    }
    if( $cols{mng_type} )
    {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_type`');
        Db->ok or die $cfg::sql_err;
    }
    if( !$cols{pon_type} )
    {
        Db->do("ALTER TABLE `pon_olt` ADD pon_type CHAR(8) CHARACTER SET utf8 COLLATE utf8_general_ci NOT NULL DEFAULT 'gpon' AFTER rw_comunity");
        Db->ok or die $cfg::sql_err;
    }
    if( !$cols{mng_tmpl} )
    {
        Db->do('ALTER TABLE `pon_olt` ADD `mng_tmpl` INT(4) NOT NULL DEFAULT '0' AFTER `pon_type`');
        Db->ok or die $cfg::sql_err;
    }
}

{
    push @warnings::messages, <<MSG
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
You need to create TRIGGER tr_aft_upd_pon!
Execute in mysql:

DROP TRIGGER IF EXISTS `tr_aft_upd_pon`;
DELIMITER //
CREATE TRIGGER `tr_aft_upd_pon` AFTER UPDATE ON `pon_bind` FOR EACH ROW
  BEGIN
    IF (NEW.rx <> OLD.rx OR NEW.tx <> OLD.tx OR NEW.status <> OLD.status) THEN
      INSERT INTO `pon_mon`(`bid`, `rx`, `tx`, `status`, `time`)
      VALUES (NEW.id, NEW.rx, NEW.tx, NEW.status, UNIX_TIMESTAMP() );
    END IF;
  END;//
DELIMITER ;

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
MSG
}

1;
