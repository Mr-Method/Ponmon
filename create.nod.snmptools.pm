#<ACTION> file=>'nod/snmptools.pm',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: SNMP tools for PON monitoring
# NoDeny: rev. 718
# Update: 2025.11.01
# ------------------------------------------------------------
package nod::snmptools;
use strict;
use Debug;

my %env_path = map{ $_ => 1 } split /\:/, $ENV{'PATH'}.':/usr/local/bin:/usr/bin:/bin';
$ENV{'PATH'} = join(':', keys %env_path);

sub new {
    my ($class, $olt) = @_;
    my $obj = {};
    $obj->{host}      = $olt->{ip};
    $obj->{port}      = int($olt->{cfg}{snmp_port} // 161);
    $obj->{version}   = $olt->{cfg}{snmp_version} // '2c';
    $obj->{timeout}   = int($olt->{cfg}{snmp_timeout} // 10);
    $obj->{retries}   = int($olt->{cfg}{snmp_retries} // 10);
    $obj->{repeaters} = int($olt->{cfg}{snmp_repeaters} // 0);

    $obj->{community_ro} = $olt->{cfg}{snmp_community_ro} || 'public';
    $obj->{community_rw} = $olt->{cfg}{snmp_community_rw} || 'private';
    $obj->{version} = $obj->{version} =~ /1|3/ ? $obj->{version} : '2c';
    bless $obj, $class;
    return $obj;
}

########################################################################################
# Performs an SNMP GET and returns the response as a Hashref.
########################################################################################
sub get {
    my ($self, $oids) = @_;
    my %resp = ();
    foreach my $oid (keys %{$oids}) {
        # debug "$oid => $oids->{$oid}";
        debug "snmpget -r $self->{retries} -t $self->{timeout} -v $self->{version} -On -Oe -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid}";
        my $output = `snmpget -r $self->{retries} -t $self->{timeout} -v $self->{version} -On -Oe -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid} 2>/dev/null`;
        if ($output =~ /\s*(\.?[\d\.]*)\s*\=\s*([\w\-]*)\:\s*((.*\s?)+)\s*$/) {
            my ($index, $value) = ($1, $3);
            $value =~ s/^\s*|\s*$//gm;
            $resp{$oid} = $value;
        }
    }
    # debug 'pre', \%resp;
    return \%resp;
}

########################################################################################
# Performs an SNMP SET and returns the response as a Hashref.
########################################################################################
sub set {
    my ($self, $oids) = @_;

    return { error => 'Invalid OIDs array' } unless ref($oids) eq 'ARRAY' && @$oids;
    my $cmd = "snmpset -t $self->{timeout} -v $self->{version} -c $self->{community_rw} -On -Ir $self->{host}:$self->{port}";
    foreach my $oid (@$oids) {
        return { error => 'Each OID must have oid, type, and value' } unless (ref($oid) eq 'HASH' && exists $oid->{oid} && exists $oid->{type} && exists $oid->{value});
        $cmd .= ' ' . $oid->{oid} . ' ' . $oid->{type} . ' ' . $oid->{value};
    }

    my $output = `$cmd 2>/dev/null`;
    debug 'pre', $output;
    return $? == 0 ? { success => 1, output => $output } : { error => "Command failed: $cmd" };
}

########################################################################################
# Performs an SNMP WALK and returns the response as a Hashref.
########################################################################################
sub walk {
    my ($self, $oids) = @_;
    my %resp = ();
    foreach my $oid (keys %{$oids}) {
        #debug "$oid => $oids->{$oid}\n";
        my @output = ();
        if (int($self->{repeaters}) == 1) {
            debug "snmpbulkwalk -On -Oe -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid}";
            @output = `snmpbulkwalk -On -Oe -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid} 2>/dev/null`;
        } elsif (int($self->{repeaters}) > 1) {
            debug "snmpbulkwalk -On -Oe -Cn1 -Cr$self->{repeaters} -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid}";
            @output = `snmpbulkwalk -On -Oe -Cn1 -Cr$self->{repeaters} -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid} 2>/dev/null`;
        } else {
            debug "snmpwalk -On -Oe -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid}";
            @output = `snmpwalk -On -Oe -r $self->{retries} -t $self->{timeout} -v $self->{version} -c $self->{community_ro} $self->{host}:$self->{port} $oids->{$oid} 2>/dev/null`;
        }
        $resp{$oid} = to_hash($oids->{$oid}, \@output);
    }
#    debug 'pre', \%resp;
    return \%resp;
}

########################################################################################
# Helper function to convert SNMP walk output to a Hashref.
########################################################################################
sub to_hash {
    my $oid = shift;
    my $output = shift;
    my %values;
    foreach my $line (@{$output}) {
        chomp $line;
        $line =~ s/$oid//;
        if ($line =~ /^\s*\.*([\d\.]*)\s*\=\s*[\w\-]*\:\s*(.*)\s*$/) {
            my ($index, $value) = ($1, $2);
            $value =~ s/^\s*|\s*$//gm;
            $values{$index} = $value;
        }
    }
    return \%values;
}

1;
