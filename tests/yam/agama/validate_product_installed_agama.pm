# SUSE's openQA tests
#
# Copyright 2023 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Validate that the product installed by agama via /etc/os-release
# Maintainer: QE YaST and Migration (QE Yam) <qe-yam at suse de>

use base "consoletest";
use strict;
use warnings;
use testapi;
use Config::Tiny;
use Test::Assert ':all';
use scheduler 'get_test_suite_data';

sub run {
    select_console 'root-console';

    my ($product) = @{get_test_suite_data()->{test_data}}{"product"};
    record_info('$product', $product);

    my $os_release_output = script_output('cat /etc/os-release');
    my $os_release_name = Config::Tiny->read_string($os_release_output)->{_}->{NAME};

    record_info('os_release_name', $os_release_name);
    assert_equals($product, $os_release_name, 'Wrong product NAME in /etc/os-release');
}

1;
