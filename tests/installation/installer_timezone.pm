# SUSE's openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

# Summary: Verify timezone settings page and proceed to next page
# - Proceed only if in timezone selection screen
# - If TIMEZONE is "beijing", select timezone-beijing in timezone selection
# screen
# - Select next
# Maintainer: Rodion Iafarov <riafarov@suse.com>

use base 'y2_installbase';
use strict;
use warnings;
use testapi;
use utils 'noupdatestep_is_applicable';

sub run {
    assert_screen "inst-timezone", 125 || die 'no timezone';
    # performance ci need install with timezone Asia-beijing
    if (check_var('TIMEZONE', 'beijing')) {
        send_key_until_needlematch("timezone-Asia", "up", 20, 1);
        send_key 'tab';
        send_key_until_needlematch("timezone-beijing", "down", 20, 1);
    }
    # Unpredictable hotkey on kde live distri, click button. See bsc#1045798
    if (noupdatestep_is_applicable() && get_var("LIVECD")) {
        assert_and_click 'next-button';
    }
    else {
        send_key $cmd{next};
    }
}

1;
