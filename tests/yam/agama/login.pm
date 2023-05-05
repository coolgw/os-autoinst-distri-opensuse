package login;

# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: login console
# Maintainer: Wei Gao <wegao@suse.com>

use base 'consoletest';
use strict;
use warnings;
use testapi;

sub run {
    my $self = shift;
    select_console 'root-console';
    record_info("console logined");
    assert_script_run("cat /etc/os-release");
}

1;
