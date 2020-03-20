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
