# SUSE's openQA tests
#
# Copyright 2023-2026 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: Executes liburing testing suite
# Maintainer: Kernel QE <kernel-qa@suse.de>
# More documentation is at the bottom

use Mojo::Base 'opensusebasetest';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils;
use version_utils 'is_transactional';
use LTP::WhiteList;
use repo_tools 'add_qa_head_repo';
use package_utils 'install_package';

sub run {
    my $self = shift;

    select_serial_terminal;

    my $install = get_var('LIBURING_INSTALL', 'from_repo');
    my $timeout = get_var('LIBURING_TIMEOUT', 1800);
    my $exclude = get_var('LIBURING_EXCLUDE', '');
    my $issues = get_var('LIBURING_KNOWN_ISSUES', '');
    my $whitelist = LTP::WhiteList->new($issues);
    my $test_dir;
    my $out;

    record_info('KERNEL', script_output('rpm -qi kernel-default'));

    if ($install =~ /git/i) {
        my $repository = get_var('LIBURING_REPO', 'https://github.com/axboe/liburing.git');
        my $version = get_var('LIBURING_VERSION', 'liburing-2.15') || 'liburing-2.15';
        my $pkgs = "git-core";

        $pkgs .= " liburing2" if script_run('rpm -q liburing2');
        install_package('-t pattern devel_basis');
        install_package($pkgs, trup_continue => 1, trup_apply => 1);

        if ($version eq '') {
            $out = script_output('rpm -q --qf "%{Version}\n" liburing2 | sort -nr | head -1');
            $version = "liburing-$out";
        }

        assert_script_run("git clone --depth=1 --branch $version $repository");
        assert_script_run("cd liburing");
        record_info("test version", script_output("git log -1 --oneline"));
        assert_script_run("CFLAGS='-g -O2 -fno-stack-protector' ./configure");
        assert_script_run("make CFLAGS='-g -O2 -fno-stack-protector' -C src");
        assert_script_run("make CFLAGS='-g -O2 -fno-stack-protector' -C test", timeout => 300);
        $test_dir = 'liburing';
    } else {
        my $default_test_dir = '/usr/lib/liburing-tests';
        add_qa_head_repo(priority => 100);
        install_package('liburing-tests', trup_apply => 1);
        if (is_transactional()) {
            assert_script_run("cp -r $default_test_dir /tmp/liburing-tests");
            $test_dir = '/tmp/liburing-tests';
        } else {
            $test_dir = $default_test_dir;
        }
    }

    my $environment = {
        product => get_var('DISTRI') . ':' . get_var('VERSION'),
        revision => get_var('BUILD'),
        flavor => get_var('FLAVOR'),
        arch => get_var('ARCH'),
        backend => get_var('BACKEND'),
        kernel => script_output('uname -r'),
        libc => '',
        gcc => '',
        harness => 'SUSE OpenQA',
    };

    # run tests executables
    my $test_exclude = '';
    my @skipped = $whitelist->list_skipped_tests($environment, 'liburing');
    if (@skipped) {
        push @skipped, $exclude if $exclude;
        my @sorted = sort @skipped;
        $test_exclude = join(' ', @sorted);
        my $count = scalar @sorted;
        my @details;
        for my $test (@sorted) {
            my $entry = $whitelist->find_whitelist_entry($environment, 'liburing', $test);
            my $message = ($entry && $entry->{message}) ? $entry->{message} : '';
            push @details, $message ? "$test: $message" : $test;
        }
        record_info(
            "Exclude ($count)",
            "Excluding tests ($count):\n" . join("\n", @details),
            result => 'softfail'
        );
    }

    if ($install =~ /git/i) {
        assert_script_run("echo 'TEST_EXCLUDE=\"$test_exclude\"' > test/config.local") if $test_exclude;
        $out = script_output(
            "make -C test runtests",
            timeout => $timeout,
            proceed_on_failure => 1
        );
    } else {
        my $env = $test_exclude ? "TEST_EXCLUDE=\"$test_exclude\" " : '';
        $out = script_output(
            "cd $test_dir && ${env}./runtests.sh *.t",
            timeout => $timeout,
            proceed_on_failure => 1
        );
    }

    my @issues;
    for my $line ($out =~ /Tests timed out \(\d+\):.*/mg) {
        push @issues, map { {name => $_, retval => 'undefined', type => 'timeout'} } $line =~ /<([\w\-\.]+\.t)>/g;
    }
    for my $line ($out =~ /Tests failed \(\d+\):.*/mg) {
        push @issues, map { {name => $_, retval => 1, type => 'failure'} } $line =~ /<([\w\-\.]+\.t)>/g;
    }

    if (@issues) {
        my @names = map { $_->{name} } @issues;
        record_info("Failed/Timed-out tests", join(", ", @names));

        my @unexpected;
        for my $test (@issues) {
            $environment->{retval} = $test->{retval};
            next if $whitelist->override_known_failures($self, $environment, 'liburing', $test->{name});
            push @unexpected, $test;
        }

        if (@unexpected) {
            for my $test (@unexpected) {
                my $msg = "$test->{type}: $test->{name}";
                record_info("Unexpected $test->{type}", $msg, result => 'fail');
            }

            # =========================================================================
            # Collect full coredump GDB deep stack traces and system context
            # =========================================================================
            my $bug_info = "";
            $bug_info .= "=== 1. System & Architecture ===\n" . script_output('uname -a', proceed_on_failure => 1) . "\n\n";
            $bug_info .= "=== 2. Package Versions ===\n" . script_output('rpm -q kernel-default liburing2 glibc gcc || true', proceed_on_failure => 1) . "\n\n";

            if (script_run('which coredumpctl') == 0) {
                $bug_info .= "=== 3. Coredump Summary List ===\n" . script_output('coredumpctl list --no-legend 2>/dev/null || true', proceed_on_failure => 1) . "\n\n";

                $bug_info .= "=== 4. Coredumpctl Meta Info (Latest) ===\n" . script_output('coredumpctl info -1 2>/dev/null || true', proceed_on_failure => 1) . "\n\n";

                # Install gdb (if not already installed) and extract full "bt full" trace and registers
                if (script_run('which gdb') != 0) {
                    script_run('zypper -n in -l gdb || true', timeout => 300);
                }

                $bug_info .= "=== 5. Full GDB Backtrace with Variables & Registers ===\n";
                my $gdb_cmd = 'exe=$(coredumpctl info -1 2>/dev/null | awk \'/Executable:/ {print $2}\'); if [ -n "$exe" ]; then coredumpctl dump -o /tmp/core 2>/dev/null && gdb -batch -ex "bt full" -ex "info registers" -ex "thread apply all bt" "$exe" /tmp/core 2>&1; rm -f /tmp/core; else echo "No executable found for coredump"; fi';
                $bug_info .= script_output($gdb_cmd, proceed_on_failure => 1) . "\n\n";
            }

            $bug_info .= "=== 6. Kernel Dmesg Errors ===\n" . script_output('dmesg -T | grep -iE "error|fail|segfault|corrupt|bug" | tail -n 30 || true', proceed_on_failure => 1) . "\n";

            # Display the full gathered Bug Report directly in openQA UI
            record_info("BUG REPORT", $bug_info);

            $self->result('fail');
        }
    }
}

sub test_flags {
    return {fatal => 0};
}

1;

=head1 Description

Test module to run liburing testing suite.

=head1 Configuration

=head2 LIBURING_INSTALL

Installation method. Defaults to C<from_repo> which installs the pre-built
liburing-tests RPM from QA:Head. Set to C<from_git> to clone and build from
source instead.

=head2 LIBURING_REPO

The liburing git repository. Used only with C<LIBURING_INSTALL=from_git>.

=head2 LIBURING_VERSION

The liburing version to checkout. Used only with C<LIBURING_INSTALL=from_git>.

=head2 LIBURING_TIMEOUT

The liburing testing suite timeout.

=head2 LIBURING_EXCLUDE

The liburing tests which we want to exclude. This can be useful for debugging.

=head2 LIBURING_KNOWN_ISSUES

The liburing tests which have known issues if they fail.
