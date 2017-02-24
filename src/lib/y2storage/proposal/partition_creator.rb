#!/usr/bin/env ruby
#
# encoding: utf-8

# Copyright (c) [2015] SUSE LLC
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

require "fileutils"
require "y2storage/planned_volumes_list"
require "y2storage/disk_size"
require "y2storage/refinements"
require "y2storage/proposal/encrypter"
require "y2storage/proposal/proposed_partition"

module Y2Storage
  class Proposal
    # Class to create partitions following a given distribution represented by
    # a SpaceDistribution object
    class PartitionCreator
      using Refinements::Devicegraph
      using Refinements::DevicegraphLists
      using Y2Storage::Refinements::Disk
      include Yast::Logger

      FIRST_LOGICAL_PARTITION_NUMBER = 5 # Number of the first logical partition (/dev/sdx5)

      # Initialize.
      #
      # @param original_graph [::Storage::Devicegraph] initial devicegraph
      def initialize(original_graph)
        @original_graph = original_graph
      end

      # Returns a copy of the original devicegraph in which all the needed
      # partitions have been created.
      #
      # @param distribution [SpaceDistribution]
      # @return [::Storage::Devicegraph]
      def create_partitions(distribution)
        self.devicegraph = original_graph.duplicate
        distribution.spaces.each do |space|
          process_free_space(space.disk_space, space.partitions, space.usable_size, space.num_logical)
        end

        devicegraph
      end

    private

      # Working devicegraph
      attr_accessor :devicegraph
      attr_reader :original_graph

      # Create partitions in a single slot of free disk space.
      #
      # @param free_space [FreeDiskSpace] the slot
      # @param volumes   [PlannedVolumesList] volumes to create
      # @params usable_size [DiskSize] real space to distribute among the
      #       volumes (part of free_space could be used for data structures)
      # @param num_logical [Integer] how many volumes should be placed in
      #       logical partitions
      def process_free_space(free_space, partitions, usable_size, num_logical)
        partitions.each do |partition|
          log.info(
            "partition #{partition.mount_point}\tsize: #{partition.disk_size}\tmax: #{partition.max_disk_size} " \
            "weight: #{partition.weight}"
          )
        end

        min_grain = free_space.disk.min_grain
        sorted = sorted_partitions(partitions, usable_size, min_grain)
        partitions = distribute_space(sorted, usable_size, min_grain: min_grain)
        create_volumes_partitions(partitions, free_space, num_logical)
      end

      # Volumes sorted in the most convenient way in order to create partitions
      # for them.
      def sorted_partitions(partitions, usable_size, min_grain)
        sorted = partitions_sorted_by_attr(partitions, :disk, :max_start_offset)
        last = ProposedPartition.enforced_last(partitions, usable_size, min_grain)
        if last
          sorted.delete(last)
          sorted << last
        end
        sorted
      end

      # Creates a partition and the corresponding filesystem for each volume
      #
      # @raise an error if a volume cannot be allocated
      #
      # It tries to honor the value of #max_start_offset for each volume, but
      # it does not raise an exception if that particular requirement is
      # impossible to fulfill, since it's usually more a recommendation than a
      # hard limit.
      #
      # @param volumes [Array<PlannedVolume>]
      # @param initial_free_space [FreeDiskSpace]
      # @param num_logical [Symbol] logical partitions @see #process_space
      def create_volumes_partitions(partitions, initial_free_space, num_logical)
        partitions.each_with_index do |part, idx|
          partition_id = part.partition_id
          partition_id ||= part.mount_point == "swap" ? ::Storage::ID_SWAP : ::Storage::ID_LINUX
          begin
            space = free_space_within(initial_free_space)
            primary = partitions.size - idx > num_logical
            partition = create_partition(part, partition_id, space, primary)
            final_device = encrypter.device_for(part, partition)
            part.create_filesystem(final_device)
            devicegraph.check
          rescue ::Storage::Exception => error
            raise Error, "Error allocating #{part}. Details: #{error}"
          end
        end
      end

      # Finds the remaining free space within the scope of the disk chunk
      # defined by a (probably outdated) FreeDiskSpace object
      #
      # @param [FreeDiskSpace] the original disk chunk, the returned free
      #   space will be within this area
      def free_space_within(initial_free_space)
        disk = devicegraph.disks.with(name: initial_free_space.disk_name).first
        spaces = disk.as_not_empty { disk.free_spaces }.select do |space|
          space.region.start >= initial_free_space.region.start &&
            space.region.start < initial_free_space.region.end
        end
        raise NoDiskSpaceError, "Exhausted free space" if spaces.empty?
        spaces.first
      end

      # Create a partition for the specified volume within the specified slot
      # of free space.
      #
      # @param vol          [ProposalVolume]
      # @param partition_id [::Storage::IdNum] ::Storage::ID_Linux etc.
      # @param free_space   [FreeDiskSpace]
      # @param primary      [Boolean] whether the partition should be primary
      #                     or logical
      #
      def create_partition(part, partition_id, free_space, primary)
        log.info("Creating partition for #{part.mount_point} with #{part.disk_size}")
        disk = free_space.disk
        ptable = partition_table(disk)

        if primary
          dev_name = next_free_primary_partition_name(disk.name, ptable)
          partition_type = ::Storage::PartitionType_PRIMARY
        else
          if !ptable.has_extended
            create_extended_partition(disk, free_space.region)
            free_space = free_space_within(free_space)
          end
          dev_name = next_free_logical_partition_name(disk.name, ptable)
          partition_type = ::Storage::PartitionType_LOGICAL
        end

        region = new_region_with_size(free_space.region, part.disk_size)
        partition = ptable.create_partition(dev_name, region, partition_type)
        partition.id = partition_id
        partition.boot = !!part.bootable if ptable.partition_boot_flag_supported?
        partition
      end

      # Creates an extended partition
      #
      # @param disk [Storage::Disk]
      # @param region [Storage::Region]
      def create_extended_partition(disk, region)
        ptable = disk.partition_table
        dev_name = next_free_primary_partition_name(disk.name, ptable)
        ptable.create_partition(dev_name, region, ::Storage::PartitionType_EXTENDED)
      end

      # Return the next device name for a primary partition that is not already
      # in use.
      #
      # @return [String] device_name ("/dev/sdx1", "/dev/sdx2", ...)
      #
      def next_free_primary_partition_name(disk_name, ptable)
        # FIXME: This is broken by design. create_partition needs to return
        # this information, not get it as an input parameter.
        part_names = ptable.partitions.to_a.map(&:name)
        1.upto(ptable.max_primary) do |i|
          dev_name = "#{disk_name}#{i}"
          return dev_name unless part_names.include?(dev_name)
        end
        raise NoMorePartitionSlotError
      end

      # Return the next device name for a logical partition that is not already
      # in use. The first one is always /dev/sdx5.
      #
      # @return [String] device_name ("/dev/sdx5", "/dev/sdx6", ...)
      #
      def next_free_logical_partition_name(disk_name, ptable)
        # FIXME: This is broken by design. create_partition needs to return
        # this information, not get it as an input parameter.
        part_names = ptable.partitions.to_a.map(&:name)
        FIRST_LOGICAL_PARTITION_NUMBER.upto(ptable.max_logical) do |i|
          dev_name = "#{disk_name}#{i}"
          return dev_name unless part_names.include?(dev_name)
        end
        raise NoMorePartitionSlotError
      end

      # Create a new region from the given one, but with new size
      # disk_size.
      #
      # @param region [::Storage::Region] initial region
      # @param disk_size [DiskSize] new size of the region
      #
      # @return [::Storage::Region] Newly created region
      #
      def new_region_with_size(region, disk_size)
        blocks = disk_size.to_i / region.block_size
        # Never exceed the region
        if region.start + blocks > region.end
          blocks = region.end - region.start + 1
        end
        # region.dup doesn't seem to work (SWIG bindings problem?)
        ::Storage::Region.new(region.start, blocks, region.block_size)
      end

      # Returns the partition table for disk, creating an empty one if needed
      #
      # @param [Storage::Disk]
      # @return [Storage::PartitionTable]
      def partition_table(disk)
        disk.partition_table
      rescue Storage::WrongNumberOfChildren
        disk.create_partition_table(disk.preferred_ptable_type)
      end

      def encrypter
        @encrypter ||= Encrypter.new
      end


      # FIXME

      def distribute_space(partitions, space_size, rounding: nil, min_grain: nil)
        raise RuntimeError if space_size < ProposedPartition.disk_size(partitions)

        rounding ||= min_grain
        rounding ||= DiskSize.new(1)

        partitions.each do |partition|
          partition.disk_size = partition.disk_size.ceil(rounding)
        end
        adjust_size_to_last_slot!(partitions.last, space_size, min_grain) if min_grain
        extra_size = space_size - ProposedPartition.total_disk_size(partitions)
        unused = distribute_extra_space!(partitions, extra_size, rounding)
        partitions.last.disk_size += unused if min_grain && unused < min_grain

        partitions
      end

      # @return [DiskSize] Surplus space that could not be distributed
      def distribute_extra_space!(partitions, extra_size, rounding)
        candidates = partitions

        while distributable?(extra_size, rounding)
          candidates = extra_space_candidates(partitions)
          return extra_size if candidates.empty?
          return extra_size if ProposedPartition.total_weight(candidates).zero?
          log.info("Distributing #{extra_size} extra space among #{candidates.size} volumes")

          assigned_size = DiskSize.zero
          total_weight = ProposedPartition.total_weight(candidates)
          candidates.each do |part|
            partition_extra = partition_extra_size(part, extra_size, total_weight, assigned_size, rounding)
            part.disk_size += partition_extra
            log.info("Distributing #{partition_extra} to #{part.mount_point}; now #{part.disk_size}")
            assigned_size += partition_extra
          end
          extra_size -= assigned_size
        end
        log.info("Could not distribute #{extra_size}") unless extra_size.zero?
        extra_size
      end

      def distributable?(size, rounding)
        size >= rounding
      end

      # Volumes that may grow when distributing the extra space
      #
      # @param volumes [PlannedVolumesList] initial set of all volumes
      # @return [PlannedVolumesList]
      def extra_space_candidates(partitions)
        partitions.select { |partition| partition.disk_size < partition.max_disk_size}
      end

      def adjust_size_to_last_slot!(partition, space_size, min_grain)
        adjusted_size = adjusted_size_after_ceil(partition, space_size, min_grain)
        target_size = partition.disk_size
        partition.disk_size = adjusted_size unless adjusted_size < target_size
      end

      def adjusted_size_after_ceil(partition, space_size, min_grain)
        mod = space_size % min_grain
        last_slot_size = mod.zero? ? min_grain : mod
        return partition.disk_size if last_slot_size == min_grain

        missing = min_grain - last_slot_size
        partition.disk_size - missing
      end

      # Extra space to be assigned to a volume
      #
      # @param volume [PlannedVolume] volume to enlarge
      # @param total_size [DiskSize] free space to be distributed among
      #    involved volumes
      # @param total_weight [Float] sum of the weights of all involved volumes
      # @param assigned_size [DiskSize] space already distributed to other volumes
      # @param rounding [DiskSize] size to round up
      #
      # @return [DiskSize]
      def partition_extra_size(partition, total_size, total_weight, assigned_size, rounding)
        available_size = total_size - assigned_size

        extra_size = total_size * (partition.weight / total_weight)
        extra_size = extra_size.ceil(rounding)
        extra_size = available_size.floor(rounding) if extra_size > available_size

        new_size = extra_size + partition.disk_size
        if new_size > partition.max_disk_size
          # Increase just until reaching the max size
          partition.max_disk_size - partition.disk_size
        else
          extra_size
        end
      end

      def partitions_sorted_by_attr(partitions, *attrs, nils_first: false, descending: false)
        partitions.each_with_index.sort do |one, other|
          compare(one, other, attrs, nils_first, descending)
        end.map(&:first)
      end

      # FIXME

    protected

      # @param one [Array] first element: the volume, second: its original index
      # @param other [Array] same structure than previous one
      def compare(one, other, attrs, nils_first, descending)
        one_vol = one.first
        other_vol = other.first
        result = compare_attr(one_vol, other_vol, attrs.first, nils_first, descending)
        if result.zero?
          if attrs.size > 1
            # Try next attribute
            compare(one, other, attrs[1..-1], nils_first, descending)
          else
            # Keep original order by checking the indexes
            one.last <=> other.last
          end
        else
          result
        end
      end

      # @param one [PlannedVolume]
      # @param other [PlannedVolume]
      def compare_attr(one, other, attr, nils_first, descending)
        one_value = one.send(attr)
        other_value = other.send(attr)
        if one_value.nil? || other_value.nil?
          compare_with_nil(one_value, other_value, nils_first)
        else
          compare_values(one_value, other_value, descending)
        end
      end

      # @param one [PlannedVolume]
      # @param other [PlannedVolume]
      def compare_values(one, other, descending)
        if descending
          other <=> one
        else
          one <=> other
        end
      end

      # @param one [PlannedVolume]
      # @param other [PlannedVolume]
      def compare_with_nil(one, other, nils_first)
        if one.nil? && other.nil?
          0
        elsif nils_first
          one.nil? ? -1 : 1
        else
          one.nil? ? 1 : -1
        end
      end

    end
  end
end
