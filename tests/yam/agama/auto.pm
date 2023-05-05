## Copyright 2023 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: First installation using D-Installer current CLI (only for development purpose)
# Maintainer: QE YaST and Migration (QE Yam) <qe-yam at suse de>

use base 'y2_installbase';
use strict;
use warnings;

use testapi;
use serial_terminal;


sub run {
    assert_screen('agama-main-page', 120);

    #Installing screen sometimes can not captured
    check_screen('agama-installing', 60);

    #Password should same as auto.sh or json
    $testapi::password = 'nots3cr3t';

    my @tags = ("welcome-to", "login");
    assert_screen \@tags, 960;
}


sub post_fail_hook {
	$testapi::password = 'linux';
	select_serial_terminal;
	script_run('journalctl -u agama-auto');
}

1;
