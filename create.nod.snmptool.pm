#<ACTION> file=>'nod/snmptool.pm',hook=>'new'
# -------------------------- NoDeny --------------------------
# Created by Redmen for NoDeny Next (https://nodeny.com.ua)
# https://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ------------------------------------------------------------
# Info: SNMP tool for PON monitoring
# NoDeny revision: 715
# Updated date: 2025.08.20
# ------------------------------------------------------------
package nod::snmptool;
use strict;
use Debug;

use Net::SNMP::Util qw(:para);
use Net::SNMP::Util::OID qw(*);

sub new {
    my ($class, $olt) = @_;
    my $obj = {};
    $obj->{host}      = $olt->{ip};
    $obj->{port}      = $olt->{cfg}{snmp_port}      || $olt->{snmp_port} || 161;
    $obj->{version}   = $olt->{cfg}{snmp_version}   || $olt->{snmp_v} || '2c';
    $obj->{timeout}   = $olt->{cfg}{snmp_timeout}   || 10;
    $obj->{retries}   = $olt->{cfg}{snmp_retries}   || 10;
    $obj->{repeaters} = $olt->{cfg}{snmp_repeaters} || 32;

    $obj->{community_ro} = $olt->{cfg}{snmp_community_ro} || 'public';
    $obj->{community_rw} = $olt->{cfg}{snmp_community_rw} || 'private';
    $obj->{version} = $obj->{version} =~ /1|3/ ? $obj->{version} : '2c';
    bless $obj, $class;
    return $obj;
}

sub get {
    my ($self, $olt, $oid) = @_;
    no strict 'refs';

    my ($result, $error) = snmpparaget(
        snmp  => {
            -hostname  => $self->{host},
            -port      => $self->{port},
            -version   => $self->{version},
            -timeout   => $self->{timeout},
            -retries   => $self->{retries},
            -community => $self->{community_ro}
        },
        oids  => $oid,
    );
#    debug "[ERROR] $error\n" if $error;
    return $result;
}

sub walk {
    my ($self, $olt, $oid) = @_;
    no strict 'refs';

    my ($result, $error) = snmpparabulk(
        snmp  => {
            -hostname  => $self->{host},
            -port      => $self->{port},
            -version   => $self->{version},
            -timeout   => $self->{timeout},
            -retries   => $self->{retries},
            -community => $self->{community_ro}
        },
        oids  => $oid,
        -maxrepetitions => $self->{repeaters},
    );
#    debug "[ERROR] $error\n" if $error;
    return $result;
}

1;
