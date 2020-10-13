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

use base "consoletest";

use strict;
use warnings;

use testapi;
use utils 'zypper_call';
use version_utils qw(is_sle is_opensuse);
use registration "add_suseconnect_product";
use services::sssd;

sub run {
    my ($self) = @_;
    $self->select_serial_terminal();
    services::sssd::full_sssd_check();
}

1;
