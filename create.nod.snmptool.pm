#<ACTION> file=>'nod/snmptool.pm',hook=>'new'
# ------------------- NoDeny ------------------
# Created by Redmen for http://nodeny.com.ua
# http://forum.nodeny.com.ua/index.php?action=profile;u=1139
# https://t.me/MrMethod
# ---------------------------------------------
package nod::snmptool;
use strict;
use Debug;

use Net::SNMP::Util qw(:para);
use Net::SNMP::Util::OID qw(*);

sub new
{
    my($class, $param) = @_;
    my $obj = {};
    bless $obj, $class;
    return $obj;
}

sub walk
{
    my ($it, $olt, $oid) = @_;
    no strict 'refs';
#    debug($oid);
    my ($result, $error) = snmpparawalk(# = snmpwalk(
        snmp  => {
            -hostname  => $olt->{ip},
            -port      => $olt->{snmp_port} || 23,
            -version   => $olt->{snmp_v} || 2,
            -timeout   => $olt->{snmp_t} || 10,
            -retries   => $olt->{snmp_r} || 20,
            -community => $olt->{ro_comunity} || "public" },
        oids  => $oid,
    );
#    debug "[ERROR] $error\n" if $error;
    return $result;
}

sub get
{
    my ($it, $olt, $oid) = @_;
    no strict 'refs';
#    debug($oid);
    my ($result, $error) = snmpparaget(# = snmpget(
        snmp  => {
            -hostname  => $olt->{ip},
            -port      => $olt->{snmp_port}   || 23,
            -version   => $olt->{snmp_v}      || 2,
            -timeout   => $olt->{snmp_t}      || 2,
            -retries   => $olt->{snmp_r}      || 20,
            -community => $olt->{ro_comunity} || "public" },
        oids  => $oid,
    );
#    debug "[ERROR] $error\n" if $error;
    return $result;
}

1;
