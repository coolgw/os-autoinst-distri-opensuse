# SUSE's openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2017 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Check initial partitioning screen and prepare optional substeps
# - If DUALBOOT is set, keep windows partition by resizing it
# - If system uses storage NG or opensuse, add changed shortcuts
# Maintainer: Joachim Rauch <jrauch@suse.com>

use base 'y2_installbase';
use strict;
use warnings;
use testapi;
use version_utils qw(is_leap is_storage_ng is_sle is_tumbleweed);
use partition_setup qw(%partition_roles is_storage_ng_newui);

sub run {
    assert_screen 'partitioning-edit-proposal-button', 40;
    if (check_var('PARTITION_EDIT', 'ext4_btrfs')) {
wait_screen_change {
        send_key 'alt-g';
};
record_info('INFO', "after alt-g");
wait_still_screen();
save_screenshot;
wait_screen_change {
        send_key 'alt-n';
};
record_info('INFO', "after alt-n");
wait_still_screen();
save_screenshot;
wait_screen_change {
        send_key 'down';
};
record_info('INFO', "after down");
wait_still_screen();
save_screenshot;
wait_screen_change {
        send_key 'alt-f';
};
record_info('INFO', "after alt-f");
wait_still_screen();
save_screenshot;
wait_screen_change {
        type_string 'ext4';
};
record_info('INFO', "type string ext4");
wait_still_screen();
save_screenshot;
wait_screen_change {
        send_key 'alt-i';
};
record_info('INFO', "after alt-i");
wait_still_screen();
save_screenshot;
wait_screen_change {
#        send_key 'b';
};
#record_info('INFO', "after b ");
record_info('INFO', "SKIP after b ");
wait_still_screen();
save_screenshot;
        assert_screen 'partitioning-ext4_root-btrfs_home';
        send_key 'alt-n';
    }

    # Storage NG introduces a new partitioning dialog. We detect this
    # by the existence of the "Guided Setup" button and set the
    # STORAGE_NG variable so later tests know about this.
    if (match_has_tag('storage-ng')) {
        set_var('STORAGE_NG', 1);
        # Define changed shortcuts
        $cmd{addraid} = 'alt-r';
        # for newer storage-ng toolbar has changed
        $cmd{addraid}          = 'alt-d' if is_storage_ng_newui;
        $cmd{customsize}       = 'alt-o';
        $cmd{donotformat}      = 'alt-t';
        $cmd{exp_part_finish}  = 'alt-n';
        $cmd{filesystem}       = 'alt-r';
        $cmd{guidedsetup}      = 'alt-g';
        $cmd{rescandevices}    = 'alt-r';
        $cmd{resize}           = 'alt-r';
        $cmd{raw_volume}       = 'alt-r';
        $cmd{enable_snapshots} = 'alt-a';
        $cmd{addpart}          = 'alt-r' if is_storage_ng_newui;
        $cmd{addvg}            = 'alt-d';
        $cmd{addlv}            = 'alt-g';
        # Set shortcut for role selection when creating partition
        $partition_roles{raw} = $cmd{raw_volume};

        if (check_var('DISTRI', 'opensuse')) {
            $cmd{expertpartitioner} = 'alt-e';
            $cmd{enablelvm}         = 'alt-e';
            $cmd{encryptdisk}       = 'alt-a';
        }
    }

    if (get_var("DUALBOOT")) {
        assert_screen 'partitioning-windows', 40;
    }
}

1;
