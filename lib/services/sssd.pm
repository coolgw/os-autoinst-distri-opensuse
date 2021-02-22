# SUSE's openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2019 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Test the integration between SSSD and its various backends - file database, LDAP, and Kerberos
# - If distro is sle >= 15, add Packagehub and sle-module-legacy products
# - Install sssd, sssd-krb5, sssd-krb5-common, sssd-ldap, sssd-tools, openldap2,
# openldap2-client, krb5, krb5-client, krb5-server, krb5-plugin-kdb-ldap
# - If sle<15, install python-pam. Otherwise, install python3-python-pam
# - If textmode, install psmisc
# - Fetch "version_utils.sh" and "sssd-tests" from datadir
# - Run the following test scenarios: ldap, ldap-no-auth, ldap-nested-groups,
# krb. Run also "local" scenario, unless sssd version is 2.0+
# - Fetch test data from each scenario from datadir/sssd-tests
# - For each test scenario, run "test.sh" script and check output for "junit
# testsuite", "junit success", "junit endsuite", otherwise record as failure
# Maintainer: HouzuoGuo <guohouzuo@gmail.com>

package services::sssd;
use base "consoletest";
use strict;
use warnings;

use testapi;
use utils ;
use version_utils qw(is_sle is_opensuse);
use registration "add_suseconnect_product";

my @scenario_list;
my @scenario_failures;
sub prepare_env {
    if (is_sle) {
        assert_script_run 'source /etc/os-release';
        if (is_sle '>=15') {
            add_suseconnect_product('PackageHub', undef, undef, undef, 300, 1);
            add_suseconnect_product('sle-module-legacy');
        }
    }

    # Install test subjects and test scripts
    my @test_subjects = qw(
      sssd sssd-krb5 sssd-krb5-common sssd-ldap sssd-tools
      openldap2 openldap2-client
      krb5 krb5-client krb5-server krb5-plugin-kdb-ldap
    );

    # for sle 12 we still use and support python2
    push @test_subjects, 'python-pam'         if is_sle('<15');
    push @test_subjects, 'python3-python-pam' if is_sle('15+') || is_opensuse;

    if (check_var('DESKTOP', 'textmode')) {    # sssd test suite depends on killall, which is part of psmisc (enhanced_base pattern)
        zypper_call "in psmisc";
    }
    zypper_call "refresh";
    zypper_call "in @test_subjects";
    assert_script_run "cd; curl -L -v " . autoinst_url . "/data/lib/version_utils.sh > /usr/local/bin/version_utils.sh";
    assert_script_run "cd; curl -L -v " . autoinst_url . "/data/sssd-tests > sssd-tests.data && cpio -id < sssd-tests.data && mv data sssd && ls sssd";

    # debug
    script_run "pwd";
    script_run "ll";

    # Get sssd version, as 2.0+ behaves differently
    my $sssd_version = script_output('rpm -q sssd --qf \'%{VERSION}\'');

    # The test scenarios are now ready to run
    push @scenario_list, 'local' if (version->parse($sssd_version) < version->parse(2.0.0));    # sssd 2.0+ removed support of 'local'
    push @scenario_list, qw(
    ldap
    ldap-no-auth
    ldap-nested-groups
    krb
    );

}

sub d389_check {
    my %args;
    $args{ignore_failure} //= 1;
    my $sss_related_units="nscd.service nscd.socket krb5kdc.service kadmind.service slapd.service";
	# Disable potentially conflicting system services
    systemctl("stop $sss_related_units",    ignore_failure => $args{ignore_failure});
    systemctl("disable $sss_related_units",    ignore_failure => $args{ignore_failure});
    script_run "killall -TERM slapd krb5kdc kadmind";
    # try check ldap-no-auth
    script_run "cd ~/sssd/ldap-no-auth";
    # check sssd status and conf
    systemctl("status sssd",    ignore_failure => $args{ignore_failure});
    systemctl("start sssd",    ignore_failure => $args{ignore_failure});
    script_run "cat /etc/sssd/sssd.conf";
    script_run "cat /etc/nsswitch.conf";
    # Fix me nsswitch seems not correct
    script_run "sed -i 's/^passwd:.*/passwd: compat sss/' /etc/nsswitch.conf";
    script_run "sed -i 's/^group:.*/group: compat sss/' /etc/nsswitch.conf";

    script_run "cp ./sssd.conf /etc/sssd/sssd.conf";
    # Fix me we should keep correct sssd.conf before migration
    systemctl("restart sssd",    ignore_failure => $args{ignore_failure});
    script_run "pwd";
    script_run "ll";
    # Fixme, we need start openldap to kick out date base file which stored in directory   /tmp/ldap-sssdtest
    #script_run "slapd -h 'ldap:///' -f slapd.conf";
    #script_run "ldapadd -x -D 'cn=root,dc=ldapdom,dc=net' -wpass -f db.ldif";
    #script_run "killall slapd";
    script_run "sed -i 's/directory.*//' ./slapd.conf";
    # d389 tools
    zypper_call "in 389-ds";
    script_run "rpm -qa 389-ds";
    # zypper_call "in 389-ds-1.4.4.13~git0.6841d693f-1.1.x86_64";
    script_run "mkdir slapd.d";
    script_run "dscreate from-file ./instance.inf";
    script_run "dsctl localhost status";
    script_run "slaptest -f slapd.conf -F ./slapd.d";
    script_run "openldap_to_ds --confirm localhost ./slapd.d ./db.ldif";
    script_run "ldapmodify -H ldap://localhost -x -D 'cn=Directory Manager' -w YOUR_ADMIN_PASSWORD_HERE -f aci.ldif";
    script_run "dsidm localhost account list ";
    #validate_script_output("dsidm localhost account list", sub{ m/testuser1/ });
    validate_script_output("getent passwd testuser1\@ldapdom", sub { m/testuser1.*testuser1/ });

    #Manual fix memberof plugin
    script_run "dsconf localhost plugin memberof show";
    script_run "systemctl restart dirsrv\@localhost";
    script_run "dsconf localhost plugin memberof fixup dc=ldapdom,dc=net -f '(objectClass=*)'";

    # check memeberof plugin
    validate_script_output("ldapsearch -H ldap://localhost -b 'dc=ldapdom,dc=net' -s sub -x -D 'cn=Directory Manager' -w YOUR_ADMIN_PASSWORD_HERE memberof", sub{ m/memberof:.*group1/ });
}


# check sssd service before and after migration
# stage is 'before' or 'after' system migration.
sub full_sssd_check {
    my ($stage) = @_;
    $stage //= '';
    if ($stage eq 'before') {
        prepare_env;
        foreach my $scenario (@scenario_list) {
            # Download the source code of test scenario
            script_run "cd ~/sssd && curl -L -v " . autoinst_url . "/data/sssd-tests/$scenario > $scenario/cdata";
            script_run "cd $scenario && cpio -idv < cdata && mv data/* ./; ls";
            validate_script_output 'bash -x test.sh $stage', sub {
                (/junit testsuite/ && /junit success/ && /junit endsuite/) or push @scenario_failures, $scenario;
            }, 120;
        }
        if (@scenario_failures) {
            die "Some test scenarios failed: @scenario_failures";
        }
        my %args;
        $args{ignore_failure} //= 1;
        systemctl("status sssd",    ignore_failure => $args{ignore_failure});
        systemctl("enable sssd",    ignore_failure => $args{ignore_failure});
        systemctl("start sssd",    ignore_failure => $args{ignore_failure});
        systemctl("status sssd",    ignore_failure => $args{ignore_failure});
    } else {
        d389_check; 
    }
}


1;
