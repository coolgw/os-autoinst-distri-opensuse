# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.
#
# Summary: Test "# audit2allow" command with options
#          "-a / -i / -w / -R / -M / -r" can work
# Maintainer: llzhao <llzhao@suse.com>
# Tags: poo#61792, tc#1741285

use base 'opensusebasetest';
use strict;
use warnings;
use testapi;
use utils;

sub run {
    my ($self)      = @_;
    my $testfile    = "test_file";
    my $test_module = "test_module";
    my $audit_log   = "/var/log/audit/audit.log";

    $self->select_serial_terminal;

    assert_script_run("systemctl restart auditd");

    # read input from logs and translate to why
    validate_script_output("audit2allow -a",            sub { m/allow\ .*_t\ .*;.*/sx });
    validate_script_output("audit2allow -i $audit_log", sub { m/allow\ .*_t\ .*;.*/sx });
    validate_script_output(
        "audit2allow -w -i $audit_log",
        sub {
            m/
	    type=.*AVC.*denied.*
	    Was\ caused\ by:.*
	    You\ can\ use\ audit2allow\ to\ generate\ a\ loadable\ module\ to\ allow\ this\ access.*/sx
        });

    # create an SELinux module, make this policy package active, check the new added module
    validate_script_output(
        "cat $audit_log | audit2allow -M $test_module",
        sub {
            m/
            To\ make\ this\ policy\ package\ active,\ execute:.*
            semodule\ -i\ $test_module.*\./sx
        });
    assert_script_run("semodule\ -i ${test_module}.pp");
    validate_script_output("semodule -lfull", sub { m/$test_module\ .*pp.*/sx });

    # remove the new added module for a cleanup, and check the cleanup
    assert_script_run("semodule -r $test_module", sub { m/Removing.*\ $test_module\ .*/sx });
    my $ret = script_run("semodule -lfull | grep ${test_module}");
    if (!$ret) {
        die "ERROR:\ \"$test_module\"\ module\ was\ not\ removed!";
    }
}

1;
