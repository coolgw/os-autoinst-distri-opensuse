# SUSE's openQA tests
#
# Copyright © 2019-2021 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved. This file is offered as-is,
# without any warranty.

# Summary: The class represents Sle12 distribution and provides access to its
# features.
# Follows the "Factory first" rule. So that the feature first appears in
# Tumbleweed distribution, and only if it behaves different in Sle12 then it
# should be overriden here.

# Maintainer: QE YaST <qa-sle-yast@suse.de>

package Distribution::Sle::12;
use strict;
use warnings FATAL => 'all';
use parent 'Distribution::Opensuse::Tumbleweed';
use Installation::Partitioner::Libstorage::EditProposalSettingsController;
use Installation::Partitioner::Libstorage::ExpertPartitionerController;
use YaST::NetworkSettings::v3::NetworkSettingsController;

sub get_partitioner {
    return Installation::Partitioner::Libstorage::EditProposalSettingsController->new();
}

sub get_expert_partitioner {
    return Installation::Partitioner::Libstorage::ExpertPartitionerController->new();
}

sub get_network_settings {
    return YaST::NetworkSettings::v3::NetworkSettingsController->new();
}

1;
