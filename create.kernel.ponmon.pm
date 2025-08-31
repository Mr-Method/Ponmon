#<ACTION> file=>'kernel/ponmon.pm',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny Next (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor kernel
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
package kernel::ponmon;
use strict;
use Debug;

use nod::tasks;

use Time::Local;
use Time::localtime;

our @ISA = qw{kernel};

$Data::Dumper::Sortkeys = 1;

BEGIN { $SIG{'__WARN__'} = sub { debug $_[0] } }

$cfg::_tbl_name_template = 'z%d_%02d_%02d_pon';

# Таблица суточного мониторинга
$cfg::_slq_create_zpon_table.=<<SQL;
(
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `sn` char(20) NOT NULL,
  `tx` char(6) DEFAULT NULL,
  `rx` char(6) DEFAULT NULL,
  `time` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `time` (`time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
SQL

my $step = 0;
my %onu_list = ();
my $period;
my $DB_graph;

sub start {
    my (undef, $single, $config) = @_;
    my $running_threads = int($cfg::k_ponmon_max_threads) || 4;
    $config->{single_olt} ||= 0;
    $config->{period}       = int($config->{single_olt}) ? 1 : int($cfg::k_ponmon_period) ? int($cfg::k_ponmon_period) * 60 : 600;
    $config->{proc_name}    = int($config->{single_olt}) ? 'noponmon::' : 'nokernel::';
    $config->{max_procs}    = int($config->{single_olt}) ? 1 : int($cfg::k_ponmon_max_threads) ? int($cfg::k_ponmon_max_threads) : 4;
    #$config->{max_procs}    = 0 if ($single && $cfg::verbose);

    if ($cfg::ponmon_db_name) {
        my $timeout = $cfg::ponmon_db_timeout || 10;
        my $db = Db->new(
            host    => $cfg::ponmon_db_host,
            user    => $cfg::ponmon_db_login,
            pass    => $cfg::ponmon_db_password,
            db      => $cfg::ponmon_db_name,
            timeout => $timeout,
            tries   => 2,
            global  => 0,
            pool    => [],
        );
        $db->connect;
        $DB_graph = $db if $db->is_connected;
    }
    $DB_graph = Db->self unless $DB_graph;
    debug 'pre', $config;

    my %forks = ();
    my $pm = 0;
    if (!$config->{single_olt}) {
        # Видаляємо IGNORE - це конфліктує з Parallel::ForkManager
        delete $SIG{CHLD};
        require Parallel::ForkManager or die "You need install Perl module Parallel::ForkManager";
        Parallel::ForkManager->import;
        $pm = Parallel::ForkManager->new($config->{max_procs});
        # Встановлюємо власний обробник SIGCHLD для Parallel::ForkManager
        $pm->set_waitpid_blocking_sleep(0.1);
        nod::tasks->new(
            task         => sub{ main($_[0], $single, $config, $pm, \%forks) },
            period       => $config->{period},
            first_period => $single ? 0 : 6,
        );
    } else {
        nod::tasks->new(
            task         => sub{ single($_[0], $single, $config) },
            period       => 30,
            first_period => $single ? 0 : 6,
        );
    }
}

sub main {
    my ($task, $single, $config, $pm, $forks) = @_;

    $pm->is_parent or return;
    # Додаємо обробку помилок для reap_finished_children
    eval { $pm->reap_finished_children; };
    tolog "Error reaping children: $@" if $@;
    $step++;
    tolog("STEP $step START! PID [$$] with running kids: ".scalar %{$forks});
    my @pids = $pm->running_procs;
    if (scalar @pids) {
        for my $pid ($pm->running_procs) {
            my $elapsed = time - $forks->{$pid}{'time'};
            my $timeout = $forks->{$pid}{'timeout'} || ($config->{period} * 2);

            if ($elapsed > $timeout) {
                debug "Process $pid timeout after ${elapsed}s (limit: ${timeout}s), terminating...";
                # Спочатку TERM, потім KILL
                if (kill('TERM', $pid)) {
                    sleep 3; # Даємо більше часу для graceful shutdown
                    if (kill(0, $pid)) { # Перевіряємо чи процес ще живий
                        debug "Process $pid still alive, sending KILL";
                        kill 'KILL', $pid;
                    }
                }
                delete $forks->{$pid};
            }
        }
    } else {
        undef $forks;
    }

    Db->connect;

    #$pm->set_max_procs($rows*2) if int($config->{max_procs});
    #$pm->set_max_procs(`getconf _NPROCESSORS_ONLN`);
    #$pm->set_max_procs(0) if ($single && $cfg::verbose);

    $pm->run_on_finish(
        sub {
            my ($pid, $exit_code, $ident) = @_;
            delete $forks->{$pid};
            my $signal = $exit_code & 127;
            my $core_dump = $exit_code & 128;
            my $real_exit = $exit_code >> 8;

            if ($signal) {
                debug "** Process $pid (OLT: $ident->{name}) killed by signal $signal" . ($core_dump ? " with core dump" : "");
            } elsif ($real_exit) {
                debug "** Process $pid (OLT: $ident->{name}) exited with code $real_exit";
            } else {
                debug "** Process $pid (OLT: $ident->{name}) completed successfully";
            }
        }
    );

    $pm->run_on_start(
        sub {
            my ($pid, $olt)=@_;
            #debug 'pre', $olt;
            $forks->{$pid}{'time'} = time;
            $forks->{$pid}{'step'} = $step;
            $forks->{$pid}{'timeout'} = defined $olt->{cfg}{proc_fork_timeout} ? $olt->{cfg}{proc_fork_timeout} : 720;
            debug "** $olt->{name} started, pid: $pid";
        }
    );

    my $db = Db->sql("SELECT * FROM `pon_olt` WHERE `enable` = 1");
    my $rows = $db->rows || 0;
    if (!$rows) {
        debug("WARNING: Can't find enabled OLTs!!!");
        sleep 30;
    }

    WORK:
    while (my %p = $db->line) {
        $p{cfg}            = Debug->do_eval(delete $p{param}) || {};
        $p{debug}          = $cfg::verbose == 2 ? 1 : 0;
        $p{cfg}{snmp_port} = $p{cfg}{snmp_port} || $p{snmp_port} || 161;
        $p{cfg}{proc_single_sleep} //= 60;

        my $module = ucfirst(lc($p{vendor}));
        if (my $err = _load_module($module)) {
            tolog("ERROR: OLT id $p{id} ===>\t $err");
            next;
        }
        my $pkg = "nod::Pon::$module";
        next if !$pkg->can('new');
        my $olt = $pkg->new({%p});
        my $timeout = defined $p{cfg}{proc_fork_timeout} ? $p{cfg}{proc_fork_timeout} : 720;
        sleep 2;
        # Forks and returns the pid for the child:
        $pm->start(\%p) and next WORK;
        &init_pon({olt=>$olt, step=>$step, config=>$config, timeout=>$timeout*2});
        $pm->finish(\%p); # Terminates the child process
    }
    while ($pm->running_procs) {
        eval { $pm->reap_finished_children; };
        tolog "Error reaping children in cleanup: $@" if $@;
        for my $pid ($pm->running_procs) {
            if (defined $forks->{$pid} && $forks->{$pid}) {
                my $elapsed = time - $forks->{$pid}{'time'};
                my $timeout = $forks->{$pid}{'timeout'} * 2;

                if ($elapsed > $timeout) {
                    debug "Cleanup: Process $pid timeout after ${elapsed}s, killing...";
                    kill 'TERM', $pid;
                    sleep 2;
                    kill 'KILL', $pid if kill(0, $pid);
                    delete $forks->{$pid};
                } else {
                    debug "Cleanup: waiting for process $pid (${elapsed}s/${timeout}s)";
                    sleep 2;
                }
            } else {
                debug "Cleanup: orphaned process $pid, killing...";
                kill 'KILL', $pid;
            }
        }
    }
    debug "DONE";
}

sub single {
    my ($task, $single, $config) = @_;
    $step++;
    my $db = Db->sql("SELECT * FROM `pon_olt` WHERE `id` = ?", $config->{single_olt});
    my $rows = $db->rows || 0;
    if (!$rows) {
        tolog("ERROR: DB \t===> No OLT in DB!!!");
        sleep 30;
        exit;
    }
    my $sleep = 0;
    while (my %p = $db->line) {
        if ($p{enable} != 2) {
            debug "OLT id $p{id} not in single mode or disabled";
            $sleep = 30;
            last;
        }
        $p{cfg}            = Debug->do_eval(delete $p{param}) || {};
        $p{debug}          = $cfg::verbose == 2 ? 1 : 0;
        $p{cfg}{snmp_port} = $p{cfg}{snmp_port} || $p{snmp_port} || 161;
        $p{cfg}{proc_single_sleep} //= 60;

        my $module = ucfirst(lc($p{vendor}));
        if (my $err = _load_module($module)) {
            tolog("ERROR: OLT id $p{id} ===>\t $err");
            $sleep = 30;
            next;
        }
        my $pkg = "nod::Pon::$module";
        next if !$pkg->can('new');
        # next if !$pkg->can('unregistered');
        my $olt = $pkg->new({%p});
        $sleep = $p{cfg}{proc_single_sleep};
        &init_pon({olt=>$olt, step=>$step, config=>$config, timeout=>0});
    }
    debug "DONE";
    debug "Cicle sleep $sleep seconds";
    sleep $sleep;
}

sub init_pon {
    my $work = shift;
    my $olt = $work->{olt};
    my $config = $work->{config};
    $0 = $config->{proc_name}.__PACKAGE__."::".$olt->{id};
    if (!$config->{single_olt}) {
        local $SIG{ALRM} = sub {
            local $SIG{TERM} = 'IGNORE';
            kill TERM => -$$;
            tolog "CHILD PID [$$] [$0] DIE BY TIMEOUT!\n";
            die "CHILD PID [$$] [$0] DIE BY TIMEOUT!\n";
        };
        #local $SIG{ALRM} = sub {  die "CHILD PID [$$] [$0] DIE BY TIMEOUT!"};
        alarm($work->{timeout}) if $work->{timeout};
        Db->connect;
    }
    my $step = $work->{step};
    $olt->{step} = $work->{step};

    debug("STEP->$step; OLT id $olt->{id} : START");

    eval {
        my $olt_data = $olt->main($step);
        _parse_olt_data($olt_data, $olt);
        undef $olt_data;
    };

    if ($@) {
        tolog("ERROR: OLT id $olt->{id} processing failed: $@");
        exit(1); # Вихід з помилкою для дочірнього процесу
    }

    debug("STEP->$step; OLT id $olt->{id} : FINISH");
    exit(0); # Нормальний вихід для дочірнього процесу
}

sub _load_module {
    my($name) = shift;
    $name = ucfirst(lc($name));
    debug "$cfg::dir_home/nod/Pon/$name.pm";
    if (grep { $_ eq "$cfg::dir_home/nod/Pon/_$name.pm" } values %INC || grep { $_ eq "$cfg::dir_home/nod/Pon/$name.pm" } values %INC) {
        return;
    }
    eval { require "$cfg::dir_home/nod/Pon/_$name.pm" };
    my $err = "$@";
    debug 'error', $err if $err && -e "$cfg::dir_home/nod/Pon/_$name.pm";
    $err && eval { require "$cfg::dir_home/nod/Pon/$name.pm" };
    return "$@";
}

sub _parse_olt_data {
    my $olt_data = shift;
    my $olt = shift;
    my $olt_main;
    my $olt_id = $olt->{id};
    my %v_ips = ();
    my $daily_pon_tbl_name = '';

    if (defined $olt_data->{onu_list}) {
        $olt_main->{onu_list} = &_get_onu_list() || {};
        $olt_main->{onu_bind} = &_get_bind() || {};
        my $t = localtime(time);
        my ($day_now, $mon_now, $year_now) = ($t->mday, $t->mon, $t->year);
        $daily_pon_tbl_name = sprintf $cfg::_tbl_name_template, $year_now+1900, $mon_now+1, $day_now;
        $DB_graph->do("CREATE TABLE IF NOT EXISTS $daily_pon_tbl_name $cfg::_slq_create_zpon_table");
        debug $daily_pon_tbl_name, "\n";
    }

    foreach my $sn (sort keys %{$olt_data->{onu_list}}) {
        my $new_onu = $olt_data->{onu_list}{$sn};
        my $old_bind = {};
        # debug 'pre', $new_onu;
        $sn = uc($sn);
        if (!defined $olt_main->{onu_list}{$sn}) {
            my $new_onu = $olt_data->{onu_list}{$sn};
            Db->do("INSERT INTO `pon_onu` SET `sn`=?, `changed`=UNIX_TIMESTAMP() ON DUPLICATE KEY UPDATE `changed`=UNIX_TIMESTAMP()", $sn);
        }
        $new_onu->{ONU_STATUS} ||= '98:Unknown:0';
        $new_onu->{ONU_RX_POWER} = sprintf("%.2f", $new_onu->{ONU_RX_POWER} // 0);
        $new_onu->{ONU_TX_POWER} = sprintf("%.2f", $new_onu->{ONU_TX_POWER} // 0);
        if (!defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}) {
            $new_onu->{LLID} ||= '';
            Db->do(
                "INSERT INTO `pon_bind` SET `sn`=?, `olt_id`=?, `llid`=?, `name`=?, `tx`=?, `rx`=?, `status`=?, `changed`=UNIX_TIMESTAMP() ".
                "ON DUPLICATE KEY UPDATE `sn`=?, `olt_id`=?, `llid`=?, `name`=?, `tx`=?, `rx`=?, `status`=?, `changed`=UNIX_TIMESTAMP()",
                $sn, $olt_id, $new_onu->{LLID}, uc($new_onu->{NAME}), $new_onu->{ONU_TX_POWER}, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_STATUS},
                $sn, $olt_id, $new_onu->{LLID}, uc($new_onu->{NAME}), $new_onu->{ONU_TX_POWER}, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_STATUS},
            );
        } else {
            # debug 'pre', $new_onu;
            my $sql_query ='UPDATE `pon_bind` SET `changed`=UNIX_TIMESTAMP()';
            my @sql_param = ();
            my $sql_where = " WHERE `sn`=? AND `olt_id`=? AND `llid`=? LIMIT 1";
            my $data = 0;
            if (defined $new_onu->{ONU_RX_POWER}) {
                $data = 1;
                $sql_query .= ", `rx`=?";
                push @sql_param, sprintf("%.2f", $new_onu->{ONU_RX_POWER} // 0);
            }
            if (defined $new_onu->{ONU_TX_POWER}) {
                $data = 1;
                $sql_query .= ", `tx`=?";
                push @sql_param, sprintf("%.2f", $new_onu->{ONU_TX_POWER} // 0);
            }
            if ($new_onu->{ONU_STATUS}) {
                $sql_query .= ", `status`=?";
                push @sql_param, $new_onu->{ONU_STATUS};
            }
            if (defined $new_onu->{NAME} && !defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{name}) {
                $sql_query .= ", `name`=?";
                push @sql_param, uc($new_onu->{NAME});
            } elsif (defined $new_onu->{NAME} && $new_onu->{NAME} ne $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}{name}) {
                $sql_query .= ", `name`=?";
                push @sql_param, uc($new_onu->{NAME});
            }
            $sql_query =~ s/\,$//g;
            Db->do($sql_query.$sql_where, @sql_param, $sn, $olt_id, $new_onu->{LLID}) if scalar @sql_param;
            $old_bind = $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}};
        }
        # TODO: Add $rough_lvl to olt:params
        my $rough_lvl = 500;
        if (
          # TODO: Change $olt->{step} % 10 to diff time and add to olt:params
          ($olt->{step} % 10) == 1 || !defined $olt_main->{onu_bind}{$sn}{$olt_id}{$new_onu->{LLID}}
          || calc_rough($old_bind->{rx}, $new_onu->{ONU_RX_POWER}) > $rough_lvl
          || calc_rough($old_bind->{tx}, $new_onu->{ONU_TX_POWER}) > $rough_lvl
          # || sprintf("%.2f", $old_bind->{rx}) ne sprintf("%.2f", $new_onu->{ONU_RX_POWER})
          # || sprintf("%.2f", $old_bind->{tx}) ne sprintf("%.2f", $new_onu->{ONU_TX_POWER})
        ) {
            $DB_graph->do("INSERT INTO $daily_pon_tbl_name SET `sn`=?, `rx`=?, `tx`=?, `time`=UNIX_TIMESTAMP()", $sn, $new_onu->{ONU_RX_POWER}, $new_onu->{ONU_TX_POWER});
        }
    }

    if (defined $olt_data->{fdb}) {
        Db->do("UPDATE `pon_fdb` SET `mac`= REPLACE(`mac`, ':', '') WHERE `mac` LIKE '%:%'");
        foreach my $port (sort keys %{$olt_data->{fdb}}) {
            foreach my $vlan (sort keys %{$olt_data->{fdb}{$port}}) {
                foreach my $mac (sort keys %{$olt_data->{fdb}{$port}{$vlan}}) {
                    my $xname = uc($olt_data->{fdb}{$port}{$vlan}{$mac}) || '';
                    $mac =~ s/[\-\.\:]//gmi;
                    Db->do(
                        "INSERT INTO `pon_fdb` SET `mac`=?, `vlan`=?, `llid`=?, `olt_id`=?, `name`=?, `time`=UNIX_TIMESTAMP() ".
                        "ON DUPLICATE KEY UPDATE `vlan`=?, `llid`=?, `olt_id`=?, `name`=?, `time`=UNIX_TIMESTAMP()",
                        $mac, $vlan, $port, $olt_id, $xname, $vlan, $port, $olt_id, $xname
                    );
                }
            }
        }
        Db->do(
            "UPDATE `pon_fdb` AS f INNER JOIN `v_ips` AS i ON (SUBSTRING_INDEX(SUBSTRING_INDEX(i.`properties`, 'user=', -1), ';', 1) = f.`mac`) ".
            "SET f.uid=i.uid WHERE i.`auth` = 1 AND f.`olt_id` = ? AND i.`uid` > 0", $olt_id
        );
    }

#<HOOK>add_parser


    undef $olt_data;
    return;
}

sub _get_bind {
    my %onu_bind = ();
    my $db = Db->sql("SELECT * FROM `pon_bind`");
    while (my %p = $db->line) {
        $onu_bind{$p{sn}}{$p{olt_id}}{$p{llid}} = {%p};
    }
    return \%onu_bind;
}

sub _get_fdb {
    my %fdb_cache = ();
    my $db = Db->sql("SELECT * FROM `pon_fdb`");
    while (my %p = $db->line) {
        $fdb_cache{$p{mac}}{$p{vlan}}{$p{llid}} = {%p};
    }
    return \%fdb_cache;
}

sub _get_onu_list {
    my %onu_list = ();
    my $db = Db->sql("SELECT * FROM `pon_onu` WHERE 1");
    while (my %p = $db->line) {
        $onu_list{$p{sn}} = {%p};
    }
    return \%onu_list;
}

sub calc_rough {
    my ($old, $new) = @_;
    return abs(abs($old * 1000) - abs($new * 1000));
}

sub hash_merge {
    my ($left, $right) = (shift, shift);
    foreach my $key (keys %$right) {
        if (!exists $left->{$key} || $left->{$key} eq $key ||  $left->{$key} == $key) {
            $left->{$key} = $right->{$key};
        } elsif (ref $left->{$key} eq 'HASH' && ref $right->{$key} eq 'HASH') {
            $left->{$key} = &hash_merge($left->{$key}, $right->{$key});
        } elsif (ref $left->{$key} ne 'HASH') {
            print ref $left->{$key}, "\n\n\n";
        }
        #debug 'pre', $left;
    }
    return $left;
}

1;
