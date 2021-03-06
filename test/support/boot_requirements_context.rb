#!/usr/bin/env rspec
# encoding: utf-8

# Copyright (c) [2016] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "y2storage/proposal_settings"
require "y2storage/partition_tables/type"
require "y2storage/filesystems/type"

RSpec.shared_context "boot requirements" do
  def find_vol(mount_point, volumes)
    volumes.find { |p| p.mount_point == mount_point }
  end

  subject(:checker) { described_class.new(settings, devicegraph) }

  let(:root_device) { "/dev/sda" }
  let(:settings) do
    settings = Y2Storage::ProposalSettings.new
    settings.root_device = root_device
    settings.use_lvm = use_lvm
    settings.root_filesystem_type = root_filesystem_type
    settings.encryption_password = "12345678" if use_encryption
    settings
  end
  let(:storage_arch) { instance_double("::Storage::Arch") }
  let(:devicegraph) { double("Y2Storage::Devicegraph") }
  let(:dev_sda) { double("Y2Storage::Disk", name: "/dev/sda") }
  let(:dev_sdb) { double("Y2Storage::Disk", name: "/dev/sdb") }
  let(:pt_gpt) { instance_double("Y2Storage::PartitionTable") }
  let(:pt_msdos) { instance_double("Y2Storage::PartitionTable") }
  let(:sda_part_table) { pt_msdos }
  let(:root_filesystem_type) { Y2Storage::Filesystems::Type::BTRFS }
  let(:use_encryption) { false }

  before do
    Y2Storage::StorageManager.create_test_instance
    allow(Y2Storage::StorageManager.instance).to receive(:arch).and_return(storage_arch)

    allow(storage_arch).to receive(:x86?).and_return(architecture == :x86)
    allow(storage_arch).to receive(:ppc?).and_return(architecture == :ppc)
    allow(storage_arch).to receive(:s390?).and_return(architecture == :s390)

    allow(devicegraph).to receive(:disks).and_return [dev_sda, dev_sdb]

    if sda_part_table
      allow(dev_sda).to receive(:partition_table).and_return(sda_part_table)
    else
      allow(dev_sda).to receive(:partition_table).and_return(nil)
    end
    allow(dev_sda).to receive(:as_not_empty).and_yield
    allow(dev_sda).to receive(:preferred_ptable_type).and_return(Y2Storage::PartitionTables::Type::GPT)
    allow(pt_gpt).to receive(:type).and_return(Y2Storage::PartitionTables::Type::GPT)
    allow(pt_msdos).to receive(:type).and_return(Y2Storage::PartitionTables::Type::MSDOS)
  end
end
