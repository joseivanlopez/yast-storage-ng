# encoding: utf-8

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

require "cwm/widget"
require "cwm/tree_pager"
require "y2partitioner/icons"
require "y2partitioner/device_graphs"
require "y2partitioner/widgets/partition_add_button"
require "y2partitioner/widgets/device_delete_button"
require "y2partitioner/widgets/blk_device_edit_button"
require "y2partitioner/widgets/disk_expert_menu_button"
require "y2partitioner/widgets/configurable_blk_devices_table"
require "y2partitioner/widgets/disk_bar_graph"
require "y2partitioner/widgets/disk_description"
require "y2partitioner/widgets/used_devices_tab"

module Y2Partitioner
  module Widgets
    module Pages
      # Page for a disk device (disk, dasd or multipath).
      #
      # This page contains a {DiskTab} and a {PartitionsTab}. In case of multipath,
      # it also contains a {UsedDevicesTab}.
      class Disk < CWM::Page
        # @return [Y2Storage::BlkDevice] Disk device this page is about
        attr_reader :disk
        alias_method :device, :disk

        # Constructor
        #
        # @param disk [Y2Storage::Disk, Y2Storage::Dasd, Y2Storage::Multipath]
        # @param pager [CWM::TreePager]
        def initialize(disk, pager)
          textdomain "storage"

          @disk = disk
          @pager = pager
          self.widget_id = "disk:" + disk.name
        end

        # @macro seeAbstractWidget
        def label
          disk.basename
        end

        # @macro seeCustomWidget
        def contents
          icon = Icons.small_icon(Icons::HD)
          VBox(
            Left(
              HBox(
                Image(icon, ""),
                Heading(format(_("Hard Disk: %s"), disk.name))
              )
            ),
            tabs
          )
        end

      private

        # Tabs to show device data
        #
        # In general, two tabs are presented: one for the device info and
        # another one with the device partitions. When the device is a multipath,
        # a third tab is used to show the disks that belong to the multipath.
        #
        # @return [Tabs]
        def tabs
          tabs = [
            DiskTab.new(disk),
            PartitionsTab.new(disk, @pager)
          ]

          tabs << UsedDevicesTab.new(disk.parents, @pager) if disk.is?(:multipath)

          Tabs.new(*tabs)
        end
      end

      # A Tab for disk device description
      class DiskTab < CWM::Tab
        # Constructor
        #
        # @param disk [Y2Storage::BlkDevice]
        def initialize(disk)
          textdomain "storage"

          @disk = disk
        end

        # @macro seeAbstractWidget
        def label
          _("&Overview")
        end

        # @macro seeCustomWidget
        def contents
          # Page wants a WidgetTerm, not an AbstractWidget
          @contents ||= VBox(DiskDescription.new(@disk))
        end
      end

      # A Tab for disk device partitions
      class PartitionsTab < CWM::Tab
        attr_reader :disk

        # Constructor
        #
        # @param disk [Y2Storage::BlkDevice]
        # @param pager [CWM::TreePager]
        def initialize(disk, pager)
          textdomain "storage"

          @disk = disk
          @pager = pager
        end

        def initial
          true
        end

        # @macro seeAbstractWidget
        def label
          _("&Partitions")
        end

        # @macro seeCustomWidget
        def contents
          table = ConfigurableBlkDevicesTable.new(devices, @pager)
          @contents ||= VBox(
            DiskBarGraph.new(disk),
            table,
            Left(
              HBox(
                PartitionAddButton.new(device: disk),
                BlkDeviceEditButton.new(pager: @pager, table: table),
                DeviceDeleteButton.new(pager: @pager, table: table),
                HStretch(),
                DiskExpertMenuButton.new(disk: disk)
              )
            )
          )
        end

      private

        def devices
          disk.partitions
        end
      end
    end
  end
end
