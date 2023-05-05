# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: login console
# Maintainer: QE YaST and Migration (QE Yam) <qe-yam at suse de>

use base 'consoletest';
use strict;
use warnings;
use testapi;

sub run {
    my $self = shift;
    select_console 'root-console';
    assert_script_run("cat /etc/os-release");
}

1;
