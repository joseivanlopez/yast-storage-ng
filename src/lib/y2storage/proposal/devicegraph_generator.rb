#!/usr/bin/env ruby
#
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

require "storage"
require "y2storage/proposal/space_maker"
require "y2storage/proposal/partition_creator"
require "y2storage/proposal/lvm_helper"

module Y2Storage
  class Proposal
    # Class to create devicegraphs that can accommodate a given collection of
    # volumes
    class DevicegraphGenerator
      include Yast::Logger

      attr_accessor :settings

      def initialize(settings)
        @settings = settings
      end

      # Devicegraph including all the specified volumes
      #
      # @param volumes [PlannedVolumesList] volumes to accommodate
      # @param initial_graph [Devicegraph] initial devicegraph
      #           (typically the representation of the current system)
      # @param disk_analyzer [DiskAnalyzer] analysis of the initial_graph
      #
      # @return [Devicegraph]
      # @raise Proposal::Error if it was not possible to propose a devicegraph
      def devicegraph(volumes, initial_graph, space_maker)
        # We are going to alter the volumes in several ways, so let's be a
        # good citizen and do it in our own copy
        volumes = volumes.deep_dup
        add_encryption_password!(volumes)

        if settings.use_lvm
          volumes, lvm_vols = volumes.split_by(&:plain_partition?)
        else
          lvm_vols = PlannedVolumesList.new
        end

        lvm_helper = LvmHelper.new(lvm_vols, encryption_password: settings.encryption_password)
        begin
          space_result = provide_space(volumes, initial_graph, lvm_helper, space_maker)
        rescue NoDiskSpaceError
          raise if volumes.target == :min
          # Try again with the minimum size
          volumes.target = :min
          lvm_vols.target = :min
          space_result = provide_space(volumes, initial_graph, lvm_helper, space_maker)
        end

        refine_volumes!(volumes, space_result[:deleted_partitions])
        graph = create_partitions(space_result[:space_distribution], space_result[:devicegraph])
        reuse_partitions!(volumes, graph)

        if settings.use_lvm
          new_pvs = new_physical_volumes(space_result[:devicegraph], graph)
          graph = lvm_helper.create_volumes(graph, new_pvs)
        end
        graph
      end

    protected

      # Modifies planned volumes adding an encryption password.
      # Encryption password is not assigned to volumes that must
      # be created as plain partitions.
      # @param volumes [PlannedVolumesList]
      def add_encryption_password!(volumes)
        return unless settings.use_encryption
        volumes.reject(&:plain_partition?).map do |volume|
          volume.encryption_password = settings.encryption_password
        end
      end

      # Provides free disk space in the proposal devicegraph to fit the
      # volumes in.
      #
      # @raise Proposal::Error if the goal is not reached
      #
      # @param no_lvm_volumes [PlannedVolumesList] set of non-LVM volumes to
      #     make space for. The LVM volumes are already handled by
      #     space_make#lvm_helper
      # @param space_maker [SpaceMaker]
      #
      # @return [Devicegraph]
      def provide_space(no_lvm_volumes, devicegraph, lvm_helper, space_maker)
        if settings.use_lvm
          provide_space_lvm(no_lvm_volumes, devicegraph, lvm_helper, space_maker)
        else
          provide_space_no_lvm(no_lvm_volumes, devicegraph, lvm_helper, space_maker)
        end
      end

      # Variant of #provide_space when LVM is not involved
      # @see #provide_space
      def provide_space_no_lvm(volumes, devicegraph, lvm_helper, space_maker)
        result = space_maker.provide_space(devicegraph, volumes, lvm_helper)
        log.info "Found #{volumes.target} space"
        result
      end

      # Variant of #provide_space when LVM is involved. It first tries to reuse
      # the existing volume groups (one at a time). If that fails, it tries to
      # create a new volume group from scratch.
      #
      # @see #provide_space
      def provide_space_lvm(no_lvm_volumes, devicegraph, lvm_helper, space_maker)
        lvm_helper.reused_volume_group = nil

        lvm_helper.reusable_volume_groups(devicegraph).each do |vg|
          begin
            lvm_helper.reused_volume_group = vg
            result = space_maker.provide_space(devicegraph, no_lvm_volumes, lvm_helper)
            log.info "Found #{no_lvm_volumes.target} space including LVM, reusing #{vg}"
            return result
          rescue NoDiskSpaceError
            next
          end
        end

        lvm_helper.reused_volume_group = nil
        result = space_maker.provide_space(devicegraph, no_lvm_volumes, lvm_helper)
        log.info "Found #{no_lvm_volumes.target} space including LVM"

        result
      end

      # List of partitions with LVM id (i.e. potential physical volumes) that
      # are present in the new devicegraph but were not there in the old one.
      #
      # @param old_devicegraph [Devicegraph]
      # @param new_devicegraph [Devicegraph]
      # @return [Array<String>] device names of the partitions
      def new_physical_volumes(old_devicegraph, new_devicegraph)
        all_pvs = new_devicegraph.partitions.select { |p| p.id.is?(:lvm) }
        old_pv_sids = old_devicegraph.partitions.select { |p| p.id.is?(:lvm) }.map(&:sid)
        all_pvs.reject { |pv| old_pv_sids.include?(pv.sid) }.map(&:name)
      end

      # Adds some extra information to the planned volumes inferred from
      # the list of partitions deleted by the space maker.
      #
      # It enforces reuse of UUIDs and labels from the deleted swap
      # partitions.
      #
      # It modifies the passed volumes.
      #
      # @param volumes [PlannedVolumesList] list of volumes to modify
      # @param deleted_partitions [Array<Partition>] partitions
      #     deleted from the initial devicegraph
      def refine_volumes!(volumes, deleted_partitions)
        deleted_swaps = deleted_partitions.select { |part| part.id.is?(:swap) }
        new_swap_volumes = volumes.select { |vol| !vol.reuse && vol.mount_point == "swap" }

        new_swap_volumes.each_with_index do |swap_volume, idx|
          deleted_swap = deleted_swaps[idx]
          break unless deleted_swap

          swap_volume.uuid = deleted_swap.filesystem.uuid
          swap_volume.label = deleted_swap.filesystem.label
        end
      end

      # Creates partitions representing a set of volumes
      #
      # @param volumes [PlannedVolumesList] set of volumes to create
      # @param initial_graph [Devicegraph] initial devicegraph
      #
      # @return [Devicegraph]
      def create_partitions(distribution, initial_graph)
        partition_creator = PartitionCreator.new(initial_graph)
        partition_creator.create_partitions(distribution)
      end

      # Adjusts pre-existing (not created by us) partitions assigning its
      # mount point and boot flag
      #
      # It works directly on the passed devicegraph
      #
      # @param volumes [PlannedVolumesList] set of volumes to create
      # @param graph [Devicegraph] devicegraph to modify
      def reuse_partitions!(volumes, graph)
        volumes.select { |v| v.reuse }.each do |vol|
          partition = graph.partitions.detect { |part| part.name == vol.reuse }
          filesystem = partition.filesystem
          filesystem.mountpoint = vol.mount_point if vol.mount_point && !vol.mount_point.empty?
          partition.boot = true if vol.bootable
        end
      end
    end
  end
end
