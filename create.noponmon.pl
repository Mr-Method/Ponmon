#<ACTION> file=>'noponmon.pl',hook=>'new'
#!/usr/bin/perl
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny Next (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: PonMon single OLT kernel handler
# NoDeny revision: 715
# Updated date: 2025.09.01
# ------------------------------------------------------------
package kernel;
use strict;
use FindBin;
use lib $FindBin::Bin;
use nod;

my $olt_id;

my $kernel = __PACKAGE__->new(
    file_cfg => 'sat.cfg',
    default_log => 'ponmon.log',
);

$kernel->{cmd_line_options} = { 'O=i' => \$olt_id };
$kernel->{help_msg} = "    -O=numeric : required OLT id\n";
$kernel->Start;

foreach (0..499) {
    $kernel->Is_terminated && exit;
    my %p = Db->line("SELECT * FROM config ORDER BY time DESC LIMIT 1");
    %p or next; # паузу можно не делать т.к. она будет между попытками соединения в модуле Db
    $cfg::config = $p{data};
    last;
}
$cfg::config or die "Error getting config from DB";

eval "
    no strict;
    $cfg::config;
    use strict;
";

$@ && die "Error config: $@";

my $dir_modkernel = "$cfg::dir_home/kernel";
opendir(my $dh, $dir_modkernel) or die "Cannot open $dir_modkernel";
my %conf_files = map{ $_ => $_ } grep{ /.cfg$/ } readdir($dh);
closedir $dh;
map { delete $conf_files{$_} } grep{ s/^_// } keys %conf_files;

my %configs = ();

while (my ($k, $v) = each %cfg::) {
    $k =~ /^k_run_(.+)$/ or next;
    defined ${$v} or next;
    $configs{$1} = { run => int ${$v} };
}

my $config = $configs{ponmon} or die "$dir_modkernel/ponmon.cfg not found";
$config->{run} = 1;
int $olt_id or die "OLT Id required but undefined in option -O";
$config->{single_olt} = int $olt_id;
$config->{k_ponmon_period} = 1;
%configs = ('ponmon' => $config);

if ($config->{run}) {
    my $package = (-e "$dir_modkernel/_ponmon.pm") ? "kernel::_ponmon" : "kernel::ponmon";
    my $use_package = "kernel::ponmon";

    # Персональный лог для каждого модуля
    my $file_log = $use_package;
    $file_log =~ s/\W+/_/g;
    $file_log .= "_$olt_id";
    my $debug = Debug->new(
        -file     => $cfg::dir_log.$file_log.'.log',
        -type     => Debug->param(-type ),
        -nochain  => Debug->param(-nochain),
        -only_log => Debug->param(-only_log),
    );

    $debug->tolog($kernel->{log_prefix}, "Loading $package.pm");
    my $err;
    {
        local $SIG{'__DIE__'} = sub { $err = $@ };
        eval "use $package";
    }
    if ($err) {
        $debug->tolog($kernel->{log_prefix}, $err);
        die "use $package: ".$err;
    }

    $debug->tolog($kernel->{log_prefix}, 'Start');
    $use_package->start('ponmon', $config);

    no strict;
    *{$use_package.'::tolog'} = sub{
        $debug->tolog($kernel->{log_prefix}, @_);
    };
    *{$use_package.'::to_slow_log'} = sub{
        __PACKAGE__->Error($_[0], $_[1], $debug);
    };
    use strict;
}

nod::tasks->run;

1;
