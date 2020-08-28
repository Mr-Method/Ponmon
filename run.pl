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

{   # PON
    my $del_sql = "DELETE FROM pon_bind WHERE sn='__NODENY__TEST__' AND olt_id=-1 AND llid=''";
    Db->do($del_sql);
    Db->do("INSERT INTO pon_bind SET sn='__NODENY__TEST__', status=0, olt_id=-1, llid=''");
    my $id = Db::result->insertid;
    $id or last;
    if( ! Db->line("SELECT 1 FROM pon_mon WHERE bid=?", $id) )
    {
        push @warnings::messages, <<MSG
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

You need to create trigger tr_aft_ins_pon!
Execute in mysql:

DELIMITER \$\$
CREATE TRIGGER tr_aft_ins_pon AFTER INSERT ON pon_bind FOR EACH ROW
    REPLACE INTO pon_mon(bid, rx, tx, time)
    VALUES (new.id, new.rx, new.tx, new.changed);
\$\$
CREATE TRIGGER tr_aft_upd_pon AFTER UPDATE ON pon_bind FOR EACH ROW
    BEGIN
        IF (FORMAT(NEW.rx,1) <> FORMAT(OLD.rx,1) OR FORMAT(NEW.tx,1) <> FORMAT(OLD.tx,1)) THEN
            INSERT INTO pon_mon(bid, rx, tx, time) VALUES (NEW.id, NEW.rx, NEW.tx, UNIX_TIMESTAMP());
        END IF;
    END;
\$\$
DELIMITER ;

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
MSG
    } else {
        Db->line("DELETE FROM pon_mon WHERE bid=? LIMIT 1", $id)
    }

    Db->do($del_sql);
}

1;
