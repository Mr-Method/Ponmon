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
    system("cp -f $module_dir/create.nod.snmptool.pm $cfg::dir_home/nod/snmptool.pm");
}

Db->is_connected or Db->connect;
{
    my $del_sql = "DELETE FROM pon_bind WHERE sn='__NODENY__TEST__' AND olt_id=-1 AND llid=''";
    Db->do($del_sql);
    Db->do("INSERT INTO pon_bind SET sn='__NODENY__TEST__', status=0, olt_id=-1, llid=''");
    my $id = Db::result->insertid;
    $id or last;
    if (!Db->line("SELECT 1 FROM pon_mon WHERE bid=?", $id)) {
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
