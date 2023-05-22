## Copyright 2023 SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: base class for Agama tests
# Maintainer: QE YaST and Migration (QE Yam) <qe-yam at suse de>

package yam::agama::agama_base;
use base 'opensusebasetest';
use strict;
use warnings;
use testapi 'select_console';
use y2_base 'save_upload_y2logs';
use Utils::Logging 'save_and_upload_log';

sub post_fail_hook {
    my ($self) = @_;
    $testapi::password = 'linux';
    select_console 'root-console';
    y2_base::save_upload_y2logs($self, skip_logs_investigation => 1);
    save_and_upload_log('journalctl -u agama-auto', "/tmp/agama-auto-log.txt");
}

sub post_run_hook {
    # In lib/main_common.pm setting LIVETEST & LIVECD will trigger logic which set password to NULL
    # So we need set to correct password for later module test
    $testapi::password = 'nots3cr3t';
}

1;
