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

RSpec.shared_context "plain UEFI" do
  RSpec.shared_context "UEFI partition" do
    using Y2Storage::Refinements::SizeCasts

    context "if there are no EFI partitions" do
      let(:efi_partitions) { [] }

      it "requires only a new /boot/efi partition" do
        expect(checker.needed_partitions).to contain_exactly(
          an_object_having_attributes(mount_point: "/boot/efi", reuse: nil)
        )
      end
    end

    context "if there is already an EFI partition" do
      let(:efi_partitions) { [partition_double("/dev/sda1", size)] }

      context "and it does not have enough size" do
        let(:size) { 32.MiB }

        it "requires only a new /boot/efi partition" do
          expect(checker.needed_partitions).to contain_exactly(
            an_object_having_attributes(mount_point: "/boot/efi", reuse: nil)
          )
        end
      end

      context "and it has enough size" do
        let(:size) { 33.MiB }

        it "only requires to use the existing EFI partition" do
          expect(checker.needed_partitions).to contain_exactly(
            an_object_having_attributes(mount_point: "/boot/efi", reuse: "/dev/sda1")
          )
        end
      end
    end
  end

  context "with a partitions-based proposal" do
    let(:use_lvm) { false }

    include_context "UEFI partition"
  end

  context "with a LVM-based proposal" do
    let(:use_lvm) { true }

    include_context "UEFI partition"
  end

  context "with an encrypted proposal" do
    let(:use_lvm) { false }
    let(:use_encryption) { true }

    include_context "UEFI partition"
  end
end