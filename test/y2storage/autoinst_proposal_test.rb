#!/usr/bin/env rspec
# encoding: utf-8
#
# Copyright (c) [2017] SUSE LLC
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

require_relative "spec_helper"
require "storage"
require "y2storage"

describe Y2Storage::AutoinstProposal do
  subject(:proposal) { described_class.new(partitioning: partitioning, devicegraph: fake_devicegraph) }

  describe "#propose" do
    using Y2Storage::Refinements::SizeCasts

    ROOT_PART = { "filesystem" => :ext4, "mount" => "/", "size" => "25%", "label" => "new_root" }.freeze

    let(:scenario) { "windows-linux-free-pc" }

    # include_context "proposal"
    let(:root) { ROOT_PART.merge("create" => true) }

    let(:home) do
      { "filesystem" => :xfs, "mount" => "/home", "size" => "50%", "create" => true }
    end

    let(:swap) do
      { "filesystem" => :swap, "mount" => "swap", "size" => "1GB", "create" => true }
    end

    let(:partitioning) do
      [{ "device" => "/dev/sda", "use" => "all", "partitions" => [root, home] }]
    end

    before do
      fake_scenario(scenario)
    end

    context "when partitions are specified" do
      it "proposes a layout including specified partitions" do
        proposal.propose
        devicegraph = proposal.devices

        expect(devicegraph.partitions.size).to eq(2)
        root, home = devicegraph.partitions

        expect(root).to have_attributes(
          filesystem_type:       Y2Storage::Filesystems::Type::EXT4,
          filesystem_mountpoint: "/",
          size:                  125.GiB
        )

        expect(home).to have_attributes(
          filesystem_type:       Y2Storage::Filesystems::Type::XFS,
          filesystem_mountpoint: "/home",
          size:                  250.GiB
        )
      end
    end

    context "when the requested layout is not possible" do
      let(:root) { ROOT_PART.merge("create" => true, "size" => "2TB") }

      it "raises an error" do
        expect { proposal.propose }.to raise_error(Y2Storage::Error)
      end
    end

    describe "reusing partitions" do
      let(:partitioning) do
        [{ "device" => "/dev/sda", "use" => "free", "partitions" => [root] }]
      end

      context "when an existing partition_nr is specified" do
        let(:root) do
          { "filesystem" => :ext4, "mount" => "/", "partition_nr" => 1, "create" => false }
        end

        it "reuses the partition with the given partition number" do
          proposal.propose
          devicegraph = proposal.devices
          reused_part = devicegraph.partitions.find { |p| p.name == "/dev/sda1" }
          expect(reused_part.filesystem_mountpoint).to eq("/")
        end
      end

      context "when an existing label is specified" do
        let(:root) do
          { "filesystem" => :ext4, "mount" => "/", "mountby" => :label, "label" => "windows",
            "create" => false }
        end

        it "reuses the partition with the given label" do
          proposal.propose
          devicegraph = proposal.devices
          reused_part = devicegraph.partitions.find { |p| p.filesystem_label == "windows" }
          expect(reused_part.filesystem_mountpoint).to eq("/")
        end
      end
    end

    describe "removing partitions" do
      let(:scenario) { "windows-linux-free-pc" }
      let(:partitioning) { [{ "device" => "/dev/sda", "partitions" => [root], "use" => use }] }

      context "when the whole disk should be used" do
        let(:use) { "all" }

        it "removes the old partitions" do
          proposal.propose
          devicegraph = proposal.devices
          expect(devicegraph.partitions.size).to eq(1)
          part = devicegraph.partitions.first
          expect(part).to have_attributes(filesystem_label: "new_root")
        end
      end

      context "when only free space should be used" do
        let(:use) { "free" }

        it "keeps the old partitions" do
          proposal.propose
          devicegraph = proposal.devices
          labels = devicegraph.partitions.map(&:filesystem_label)
          expect(labels).to eq(["windows", "swap", "root", "new_root"])
        end

        it "raises an error if there is not enough space"
      end

      context "when only space from Linux partitions should be used" do
        let(:use) { "linux" }

        it "keeps all partitions except Linux ones" do
          proposal.propose
          devicegraph = proposal.devices
          labels = devicegraph.partitions.map(&:filesystem_label)
          expect(labels).to eq(["windows", "new_root"])
        end
      end

      context "when the device should be initialized" do
        let(:partitioning) { [{ "device" => "/dev/sda", "partitions" => [root], "initialize" => true }] }
        let(:boot_checker) { double("Y2Storage::BootRequirementsChecker", needed_partitions: []) }
        before { allow(Y2Storage::BootRequirementsChecker).to receive(:new).and_return boot_checker }

        it "removes the old partitions" do
          proposal.propose
          devicegraph = proposal.devices
          expect(devicegraph.partitions.size).to eq(1)
          part = devicegraph.partitions.first
          expect(part).to have_attributes(filesystem_label: "new_root")
        end
      end
    end

    describe "skipping a disk" do
      let(:skip_list) do
        [{ "skip_key" => "name", "skip_value" => skip_device }]
      end

      let(:partitioning) do
        [{ "use" => "all", "partitions" => [root, home], "skip_list" => skip_list }]
      end

      context "when a disk is included in the skip_list" do
        let(:skip_device) { "sda" }

        it "skips the given disk" do
          proposal.propose
          devicegraph = proposal.devices
          sdb1 = devicegraph.partitions.find { |p| p.name == "/dev/sdb1" }
          expect(sdb1).to have_attributes(filesystem_label: "new_root")
          sda1 = devicegraph.partitions.first
          expect(sda1).to have_attributes(filesystem_label: "windows")
        end
      end

      context "when no disk is included in the skip_list" do
        let(:skip_device) { "sdc" }

        it "does not skip any disk" do
          proposal.propose
          devicegraph = proposal.devices
          sda1 = devicegraph.partitions.first
          expect(sda1).to have_attributes(filesystem_label: "new_root")
        end
      end
    end

    describe "automatic partitioning" do
      let(:partitioning) do
        [{ "device" => "/dev/sdb", "use" => "all" }]
      end

      let(:settings) do
        Y2Storage::ProposalSettings.new.tap do |settings|
          settings.use_lvm = false
          settings.use_separate_home = true
        end
      end

      before do
        allow(Y2Storage::ProposalSettings).to receive(:new_for_current_product)
          .and_return(settings)
      end

      it "falls back to the product's proposal with given disks" do
        expect(Y2Storage::Proposal::DevicesPlanner).to receive(:new)
          .with(settings, Y2Storage::Devicegraph)
          .and_call_original
        proposal.propose
        devicegraph = proposal.devices
        sdb = devicegraph.disks.find { |d| d.name == "/dev/sdb" }
        expect(sdb.partitions.size).to eq(2) # / and /home
      end
    end

    describe "LVM" do
      let(:partitioning) do
        [
          { "device" => "/dev/sda", "use" => "all", "partitions" => [lvm_pv] },
          { "device" => "/dev/system", "partitions" => [root_spec], "type" => :CT_LVM }
        ]
      end

      let(:lvm_pv) do
        { "create" => true, "lvm_group" => "system", "size" => "max" }
      end

      let(:root_spec) do
        { "mount" => "/", "filesystem" => "ext4", "lv_name" => "root", "size" => "1G" }
      end

      it "creates requested volume groups" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.lvm_vgs).to contain_exactly(
          an_object_having_attributes(
            "vg_name" => "system"
          )
        )
      end

      it "creates requested logical volumes" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.lvm_lvs).to contain_exactly(
          an_object_having_attributes(
            "lv_name" => "root"
          )
        )
      end
    end

    describe "RAID" do
      let(:partitioning) do
        [
          { "device" => "/dev/sda", "use" => "all", "partitions" => [root_spec, raid_spec] },
          { "device" => "/dev/sdb", "use" => "all", "partitions" => [raid_spec] },
          { "device" => "/dev/md", "partitions" => [home_spec] }
        ]
      end

      let(:md_device) { "/dev/md1" }

      let(:home_spec) do
        {
          "mount" => "/home", "filesystem" => "xfs", "size" => "max",
          "raid_name" => md_device, "partition_nr" => 1, "raid_options" => raid_options
        }
      end

      let(:raid_options) do
        { "raid_type" => "raid1" }
      end

      let(:root_spec) do
        { "mount" => "/", "filesystem" => "ext4", "size" => "5G" }
      end

      let(:raid_spec) do
        { "raid_name" => md_device, "size" => "20GB", "partition_id" => 253 }
      end

      it "creates a RAID" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.md_raids).to contain_exactly(
          an_object_having_attributes(
            "number" => 1
          )
        )
      end

      it "adds the specified devices" do
        proposal.propose
        devicegraph = proposal.devices
        raid = devicegraph.md_raids.first
        expect(raid.devices.map(&:name)).to contain_exactly("/dev/sda2", "/dev/sdb1")
      end

      context "when using a named RAID" do
        let(:raid_options) { { "raid_name" => md_device, "raid_type" => "raid0" } }
        let(:md_device) { "/dev/md/data" }

        it "uses the name instead of a number" do
          proposal.propose
          devicegraph = proposal.devices
          expect(devicegraph.md_raids).to contain_exactly(
            an_object_having_attributes(
              "name"     => "/dev/md/data",
              "md_level" => Y2Storage::MdLevel::RAID0
            )
          )
        end
      end
    end

    describe "LVM on RAID" do
      let(:partitioning) do
        [
          { "device" => "/dev/sda", "use" => "all", "partitions" => [raid_spec] },
          { "device" => "/dev/sdb", "use" => "all", "partitions" => [raid_spec] },
          { "device" => "/dev/md", "partitions" => [md_spec] },
          { "device" => "/dev/system", "partitions" => [root_spec, home_spec], "type" => :CT_LVM }
        ]
      end

      let(:md_spec) do
        {
          "partition_nr" => 1, "raid_options" => raid_options, "lvm_group" => "system"
        }
      end

      let(:raid_options) do
        { "raid_type" => "raid0" }
      end

      let(:root_spec) do
        { "mount" => "/", "filesystem" => :ext4, "lv_name" => "root", "size" => "5G" }
      end

      let(:home_spec) do
        { "mount" => "/home", "filesystem" => :xfs, "lv_name" => "home", "size" => "5G" }
      end

      let(:raid_spec) do
        { "raid_name" => "/dev/md1", "size" => "20GB", "partition_id" => 253 }
      end

      it "creates a RAID to be used as PV" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.md_raids).to contain_exactly(
          an_object_having_attributes(
            "number"   => 1,
            "md_level" => Y2Storage::MdLevel::RAID0
          )
        )
        raid = devicegraph.md_raids.first
        expect(raid.lvm_pv.lvm_vg.vg_name).to eq("system")
      end

      it "creates requested volume groups on top of the RAID device" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.lvm_vgs).to contain_exactly(
          an_object_having_attributes(
            "vg_name" => "system"
          )
        )
        vg = devicegraph.lvm_vgs.first.lvm_pvs.first
        expect(vg.blk_device).to be_a(Y2Storage::Md)
      end

      it "creates requested logical volumes" do
        proposal.propose
        devicegraph = proposal.devices
        expect(devicegraph.lvm_lvs).to contain_exactly(
          an_object_having_attributes("lv_name" => "root", "filesystem_mountpoint" => "/"),
          an_object_having_attributes("lv_name" => "home", "filesystem_mountpoint" => "/home")
        )
      end
    end

    context "when already called" do
      before do
        proposal.propose
      end

      it "raises an error" do
        expect { proposal.propose }.to raise_error(Y2Storage::UnexpectedCallError)
      end
    end
  end
end