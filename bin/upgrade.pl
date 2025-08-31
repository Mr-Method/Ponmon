#!/usr/bin/env perl
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PON monitor upgrade system
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
use strict;
use FindBin;
use lib "$FindBin::Bin/../../../";
use Cwd 'abs_path';

use Debug;
use Db;

my $debug = 0;

$ENV{LC_ALL} //= 'C';

$SIG{'__DIE__'} = sub {
    my $err = $_[0];
    lprint("[CRITICAL] $err");
    exit;
};

$SIG{'__WARN__'} = sub {
    my $warn = $_[0];
    lprint("[WARNING] $warn");
};

$Data::Dumper::Sortkeys = 1;

$cfg::dir_home = abs_path("$FindBin::Bin/../../");
$cfg::dir_home =~ s|/[^/]+$||;

$cfg::main_config = $cfg::dir_home.'/sat.cfg';
$cfg::upgrade_log = $cfg::dir_home.'/logs/ponmon_upgrade.log';

package cfg;
require $cfg::main_config;

package main;

Db->new(
    host    => $cfg::Db_server,
    user    => $cfg::Db_user,
    pass    => $cfg::Db_pw,
    db      => $cfg::Db_name,
    timeout => $cfg::Db_connect_timeout,
    tries   => 5,
    global  => 1,
    pool    => $cfg::Db_pool || [],
);

Db->do("SET NAMES utf8");
Db->is_connected or die 'No DB connection';

Debug->flush;
tolog("[START] init upgrade");

my %p = Db->line("SELECT *, UNIX_TIMESTAMP() AS t FROM config ORDER BY time DESC LIMIT 1");
%p or die 'No config in DB';

$cfg::config = $p{data};

eval "no strict; $cfg::config;";

local $SIG{'__DIE__'} = sub {
    die @_ if $^S; # die внутри eval
};

unlink $cfg::upgrade_log;

Debug->param(
    -type     => $debug ? 'console' : 'file',
    -file     => $cfg::upgrade_log,
    -nochain  => $debug ? 0 : 1,
    # -only_log => 0,
);

sub lprint {
    my ($text) = @_;
    print $text."\n";
    tolog($text);
}

###############################################################################################################################################################

my %param_new_names = (
    'single_sleep'     => 'proc_single_sleep',
    'fork_timeout'     => 'proc_fork_timeout',
    'fdb_force_telnet' => 'telnet_fdb_force',
    'fdb_cmd'          => 'telnet_fdb_cmd',
    'telnet_enamod'    => 'telnet_enamode',
    'snmp_ro_comunity' => 'snmp_community_ro',
    'snmp_rw_comunity' => 'snmp_community_rw',
    'snmp_f'           => 'snmp_repeaters',
    'snmp_r'           => 'snmp_retries',
    'snmp_t'           => 'snmp_timeout',
    'snmp_v'           => 'snmp_version'
);

my %lang_text;
$lang_text{ua}{need_root} = "[ERROR] Цей скрипт повинен бути запущений від імені root користувача.\n";
$lang_text{en}{need_root} = "[ERROR] This script must be run as root user.\n";
$lang_text{ua}{before_start} = '[INFO] Перед запуском оновлення, ви повинні зупинити процес kernel::ponmon. Хочете продовжити? [yes/NO]: ';
$lang_text{en}{before_start} = '[INFO] Before start upgrade, you must stop kernel::ponmon process. Do you want to continue? [yes/NO]: ';
$lang_text{ua}{after_end} = '[INFO] Журнал оновлення можна переглянути тут: ';
$lang_text{en}{after_end} = '[INFO] You can view the upgrade log here: ';

my $lang = ($cfg::Lang =~ /^ua|^ru/gi) ? 'ua' : 'en';

$< == 0 or die $lang_text{$lang}{need_root};

print $lang_text{$lang}{before_start};
my $line = <STDIN>;
chomp $line;

if (lc($line) =~ /^y|yes\s*$/i) {
    lprint("[INFO] start upgrade");
    sleep 1;
} else {
    lprint("[ERROR] exit");
    sleep 1;
    exit;
}

{
    # pon_olt
    my %table_hash = %{get_table_info('pon_olt')};
    last if !scalar keys %table_hash;
    # debug('pre', \%table_hash);
    unless (exists $table_hash{param}) {
        Db->do("ALTER TABLE `pon_olt` ADD `param` VARCHAR(1024) DEFAULT NULL AFTER `firmware`");
        Db->ok or db_error();
        lprint("[INFO] add `param` column to `pon_olt` table");
    }
    unless (exists $table_hash{pon_type}) {
        Db->do("ALTER TABLE `pon_olt` ADD pon_type VARCHAR(16) CHARACTER SET utf8 NOT NULL DEFAULT 'gpon' AFTER `firmware`");
        Db->ok or db_error();
        lprint("[INFO] add `pon_type` column to `pon_olt` table");
    }

    templates2param();

    if (exists $table_hash{mng_pswd}) {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_pswd`');
        Db->ok or db_error();
        lprint("[INFO] drop `mng_pswd` column from `pon_olt` table");
    }
    if (exists $table_hash{mng_user}) {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_user`');
        Db->ok or db_error();
        lprint("[INFO] drop `mng_user` column from `pon_olt` table");
    }
    if (exists $table_hash{mng_type}) {
        Db->do('ALTER TABLE `pon_olt` DROP `mng_type`');
        Db->ok or db_error();
        lprint("[INFO] drop `mng_type` column from `pon_olt` table");
    }
    if (exists $table_hash{ro_comunity}) {
        Db->do('ALTER TABLE `pon_olt` DROP `ro_comunity`');
        Db->ok or db_error();
        lprint("[INFO] drop `ro_comunity` column from `pon_olt` table");
    }
    if (exists $table_hash{rw_comunity}) {
        Db->do('ALTER TABLE `pon_olt` DROP `rw_comunity`');
        Db->ok or db_error();
        lprint("[INFO] drop `rw_comunity` column from `pon_olt` table");
    }
    if (exists $table_hash{mng_tmpl}) {
        my %p = Db->line('SELECT COUNT(*) AS c FROM `pon_olt` WHERE `mng_tmpl`>0');
        if ($p{c} == 0) {
            Db->do('ALTER TABLE `pon_olt` DROP `mng_tmpl`');
            Db->ok or db_error();
            lprint("[INFO] drop `mng_tmpl` column from `pon_olt` table");
        }
    }
}

{
    # pon_fdb
    my %table_hash = %{get_table_info('pon_fdb')};
    last if !scalar keys %table_hash;
    # debug('pre', \%table_hash);
    if ($table_hash{ip}) {
        Db->do("ALTER TABLE `pon_fdb` DROP `ip`");
        Db->ok or db_error();
        lprint("[INFO] drop `ip` column from `pon_fdb` table");
    }
}

{
    # pon_bind
    my %table_hash = %{get_table_info('pon_bind')};
    last if !scalar keys %table_hash;
    # debug('pre', \%table_hash);
    if (exists $table_hash{id} && $table_hash{id}{type} !~ /^int|^bigint/i) {
        Db->do("ALTER TABLE `pon_bind` CHANGE `id` `id` INT UNSIGNED NOT NULL AUTO_INCREMENT");
        Db->ok or db_error();
        lprint("[INFO] change `id` column to `int` in `pon_onu` table");
    }
    if (exists $table_hash{user}) {
        Db->do("ALTER TABLE `pon_bind` DROP `user`");
        Db->ok or db_error();
        lprint("[INFO] drop `user` column from `pon_bind` table");
    }
    if (exists $table_hash{place}) {
        Db->do("ALTER TABLE `pon_bind` DROP `place`");
        Db->ok or db_error();
        lprint("[INFO] drop `place` column from `pon_bind` table");
    }
    if (exists $table_hash{dereg}) {
        Db->do("ALTER TABLE `pon_bind` DROP `dereg`");
        Db->ok or db_error();
        lprint("[INFO] drop `dereg` column from `pon_bind` table");
    }
    if (exists $table_hash{tx} && $table_hash{tx}{type} !~ /^decimal/i) {
        Db->do("ALTER TABLE `pon_bind` CHANGE `tx` `tx` DECIMAL(6,3) NOT NULL DEFAULT '0.0'");
        Db->ok or db_error();
        lprint("[INFO] change `tx` column to `decimal(6,3)` in `pon_bind` table");
    }
    if (exists $table_hash{rx} && $table_hash{rx}{type} !~ /^decimal/i) {
        Db->do("ALTER TABLE `pon_bind` CHANGE `rx` `rx` DECIMAL(6,3) NOT NULL DEFAULT '0.0'");
        Db->ok or db_error();
        lprint("[INFO] change `rx` column to `decimal(6,3)` in `pon_bind` table");
    }
}

{
    # pon_onu
    my %table_hash = %{get_table_info('pon_onu')};
    last if !scalar keys %table_hash;
    # debug('pre', \%table_hash);
    if (exists $table_hash{id} && ($table_hash{id}{type} !~ /^int|^bigint/i || $table_hash{id}{mysql_type_name} !~ /unsigned/i)) {
        Db->do("ALTER TABLE `pon_onu` CHANGE `id` `id` INT UNSIGNED NOT NULL AUTO_INCREMENT");
        Db->ok or db_error();
        lprint("[INFO] change `id` column to `int` in `pon_onu` table");
    }
    unless (exists $table_hash{place_type}) {
        Db->do("ALTER TABLE `pon_onu` ADD `place_type` VARCHAR(16) NOT NULL DEFAULT '' AFTER `firmware`, ADD KEY `place_type` (`place_type`)");
        Db->ok or db_error();
        lprint("[INFO] add `place_type` column to `pon_onu` table");
    }
    unless (exists $table_hash{place}) {
        Db->do("ALTER TABLE `pon_onu` ADD `place` int NOT NULL DEFAULT '0' AFTER `place_type`, ADD KEY `place` (`place`)");
        Db->ok or db_error();
        lprint("[INFO] add `place` column to `pon_onu` table");
    }
}

{
    # graph_log tables
    my $DB_graph = Db->self;
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
    my $dbh = $DB_graph->dbh;
    my $sth = $dbh->prepare("SHOW TABLES LIKE 'z20%_%_pon'");
    unless ($sth->execute) {
        debug 'error', 'Failed to execute sql: SHOW TABLES';
        last;
    }
    while (my $p = $sth->fetchrow_arrayref) {
        my $graph_table = $p->[0];
        $graph_table =~ /^Z(\d\d\d\d)_(\d+)_(\d+)_pon$/i or next;
        my %table_hash = %{get_table_info($graph_table)};
        next if !scalar keys %table_hash;
        # debug('pre', \%table_hash);
        unless (exists $table_hash{id}) {
            Db->do("ALTER TABLE `$graph_table` ADD `id` INT UNSIGNED NOT NULL AUTO_INCREMENT FIRST, ADD PRIMARY KEY (`id`)");
            Db->ok or db_error();
            lprint("[INFO] add `id` column to `$graph_table` table");
            $table_hash{id} = {
                name => 'id',
                type => 'int',
                nullable => 0,
                default => 0,
                size => 10,
            };
        }
        unless (exists $table_hash{sn}) {
            Db->do("ALTER TABLE `$graph_table` ADD `sn` VARCHAR(20) DEFAULT '' AFTER `id`");
            Db->ok or db_error();
            lprint("[INFO] add `sn` column to `$graph_table` table");
            $table_hash{sn} = {
                name => 'sn',
                type => 'varchar',
                nullable => 0,
                default => '',
                size => 20,
            };
        }
        if (exists $table_hash{bid} && exists $table_hash{sn}) {
            Db->do("UPDATE `$graph_table` t INNER JOIN `pon_bind` p ON t.bid = p.id SET t.sn = IFNULL(p.sn, '')");
            Db->do("DELETE FROM `$graph_table` WHERE sn = '' OR sn IS NULL");
            Db->do("ALTER TABLE `$graph_table` DROP `bid`");
            Db->ok or db_error();
            delete $table_hash{bid};
            lprint("[INFO] drop `bid` column from `$graph_table` table");
        }
    }
}

sub get_table_info {
    my ($table) = @_;
    my $st_table = Db->dbh->column_info(undef, undef, $table, undef);
    my %cols = ();
    while (my $table_hash = $st_table->fetchrow_hashref()) {
        $cols{$table_hash->{COLUMN_NAME}} = {
            'name' => $table_hash->{COLUMN_NAME},
            'type' => $table_hash->{TYPE_NAME},
            'nullable' => $table_hash->{NULLABLE},
            'default'  => $table_hash->{COLUMN_DEF},
            'size' => $table_hash->{COLUMN_SIZE},
            'mysql_type_name' => $table_hash->{mysql_type_name},
            'mysql_is_auto_increment' => $table_hash->{mysql_is_auto_increment},
            'mysql_is_pri_key' => $table_hash->{mysql_is_pri_key},
        };
        $cols{$table_hash->{COLUMN_NAME}}{values} = $table_hash->{mysql_values} if $table_hash->{mysql_values};
    }
    return {%cols};
    # https://github.com/wickedest/Mergely

    # my $tts = Db->sql('SHOW CREATE TABLE pon_olt;');
    # my $tts = Db->sql('DESCRIBE pon_olt;');
    # my $tts = Db->sql('SHOW INDEX FROM pon_olt;');
    # while (my %p = $tts->line) {
    #     debug('pre', \%p);
    # }
}

sub db_error {
    if (my $err = $DBI::errstr) {
        lprint("[ERROR] MySQL Error: $err");
        exit;
    }
}

sub templates2param {
    my $db = Db->sql('SELECT * FROM `pon_olt` ORDER BY `id`');
    Db->ok or db_error();
    while (my %p = $db->line) {
        $p{param} = Debug->do_eval($p{param}) || {};
        my $mng_tmpl = exists $p{'mng_tmpl'} && $p{'mng_tmpl'} > 0 ? int($p{'mng_tmpl'}) : 0;
        my %settings = ();
        if ($mng_tmpl) {
            my %x = Db->line('SELECT * FROM `documents` WHERE `id`=? AND `is_section`=0', $mng_tmpl);
            if ($x{id} == $mng_tmpl) {
                $x{document} =~ s/\r//gm;
                foreach my $line (split /\n/, $x{document}) {
                    chomp($line);
                    $line =~ /([^=\s]+)\s*=\s*(.+)/ or next;
                    my ($k, $v) = ($1, $2);
                    $k =~ s/^\s*|\s*$//g;
                    $v =~ s/^\s*|\s*$//g;
                    $settings{$k} = $v;
                }
                chomp(%settings);
            }
        }
        my $sl = scalar %settings;
        foreach my $key (keys %{$p{param}}) {
            my $val = $p{param}{$key};
            $key =~ s/^\s*|\s*$//gm;
            $val =~ s/^\s*|\s*$//gm;
            next if (!length $key || !length $val);
            $settings{$key} = $val;
        }

        my $changes = 0;
        foreach my $key (keys %param_new_names) {
            if (exists $settings{$key} && !exists $settings{$param_new_names{$key}}) {
                $settings{$param_new_names{$key}} = delete $settings{$key};
                lprint("[INFO] rename `{$key}` to `{$param_new_names{$key}}` in param from template `{$p{mng_tmpl}}`");
                $changes++;
            }
        }
        if (!exists $settings{snmp_community_ro} && defined $p{ro_comunity} && $p{ro_comunity}) {
            $settings{snmp_community_ro} = $p{ro_comunity};
            $changes++;
            lprint("[INFO] rename `ro_comunity` to `snmp_community_ro` in param from template `{$p{mng_tmpl}}`");
        }
        if (!exists $settings{snmp_community_rw} && defined $p{rw_comunity} && $p{rw_comunity}) {
            $changes++;
            $settings{snmp_community_rw} = $p{rw_comunity};
            lprint("[INFO] rename `rw_comunity` to `snmp_community_rw` in param from template `{$p{mng_tmpl}}`");
        }
        my $param = Debug->dump(\%settings);

        if ($p{mng_tmpl} && $changes) {
            Db->do("UPDATE `pon_olt` SET `param`=?, `changed`=UNIX_TIMESTAMP() WHERE `id`=?", $param, $p{'id'});
            Db->ok or db_error();
            Db->do("UPDATE `pon_olt` SET `mng_tmpl`=0 WHERE `id`=?", $p{'id'});
            lprint("[INFO] update `pon_olt` table with new param from template `{$p{mng_tmpl}}`");
        }
        if ($changes) {
            Db->do("UPDATE `pon_olt` SET `param`=?, `changed`=UNIX_TIMESTAMP() WHERE `id`=?", $param, $p{'id'});
            lprint("[INFO] update `pon_olt` table with new param");
        }
    }
}

lprint("[SUCCESS] upgrade completed");

END {
    print $lang_text{$lang}{after_end}."$cfg::upgrade_log\n";
    sleep 1;
    exit;
}

1;
