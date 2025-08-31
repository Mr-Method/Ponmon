#<ACTION> file=>'kernel/ponmon_clean.pm',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor kernel clean
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
package kernel::ponmon_clean;
use strict;
use nod::tasks;

use Debug;
use Time::Local;

our @ISA = qw{kernel};

$cfg::k_ponmon_max_fdbtime  ||= 3;
$cfg::k_ponmon_max_bindtime ||= 7;

sub start {
    my (undef, $single, $config) = @_;
    $config->{period} //= 12;

    nod::tasks->new(
        task         => sub{ clean($_[0], $single, $config) },
        period       => $config->{period} * 3600,
        first_period => $single ? 0 : 6,
    );
}

sub clean {
    my ($task, $single, $config) = @_;

    my $DB_graph;
    if ($cfg::ponmon_db_name) {
        my $timeout = $cfg::ponmon_db_timeout || 10;
        my $db = Db->new(
            host    => $cfg::ponmon_db_host,
            user    => $cfg::ponmon_db_login,
            pass    => $cfg::ponmon_db_password,
            db      => $cfg::ponmon_db_name,
            timeout => $timeout,
            tries   => 3,
            global  => 0,
            pool    => [],
        );
        $db->connect;
        $DB_graph = $db if $db->is_connected;
    }
    $DB_graph = Db->self unless $DB_graph;

    if (!!$cfg::ponmon_web_user_sn_field && !!$cfg::ponmon_web_user_sn_copy) {
        eval {
           Db->do(
               "UPDATE data0 d0 INNER JOIN `pon_fdb` pf ON (d0.uid = pf.uid) LEFT JOIN `pon_bind` pb ON (pb.olt_id = pf.olt_id AND pb.llid = pf.llid) ".
               "SET d0.".Db->filtr($cfg::ponmon_web_user_sn_field)." = pb.sn ".
               "WHERE d0.".Db->filtr($cfg::ponmon_web_user_sn_field)." = '' AND pb.sn IS NOT NULL"
           );
        }
    }

    Db->do("DELETE FROM pon_fdb WHERE time < UNIX_TIMESTAMP(NOW() - INTERVAL ? DAY)",     int($cfg::k_ponmon_max_fdbtime))  if int($cfg::k_ponmon_max_fdbtime)  > 0;
    Db->do("DELETE FROM pon_bind WHERE changed < UNIX_TIMESTAMP(NOW() - INTERVAL ? DAY)", int($cfg::k_ponmon_max_bindtime)) if int($cfg::k_ponmon_max_bindtime) > 0;

    my $max_history = int($cfg::k_ponmon_max_history) || 0;
    if ($max_history > 0) {
        my $dbh = $DB_graph->dbh;
        my $sth = $dbh->prepare("SHOW TABLES LIKE 'z20%_%_pon'");
        if (!$sth->execute) {
            debug 'error', 'Не выполнен sql: SHOW TABLES';
            return;
        }
        my $Z_time = time() - ($cfg::k_ponmon_max_history || 60) * 24 * 3600;
        while (my $p = $sth->fetchrow_arrayref) {
            $p->[0] =~ /^Z(\d\d\d\d)_(\d+)_(\d+)_pon$/i or next;
            my $time = timelocal(59,59,23,$3,$2-1,$1);
            if ($time < $Z_time) {
                $DB_graph->do("DROP table $p->[0] ");
            }
        }
    }
    debug 'DONE';
}

1;
