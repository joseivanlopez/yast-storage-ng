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

require "y2partitioner/widgets/tabs"
require "y2partitioner/icons"
require "y2partitioner/widgets/pages/base"
require "y2partitioner/widgets/pages/lvm"
require "y2partitioner/widgets/configurable_blk_devices_table"
require "y2partitioner/widgets/lvm_devices_table"
require "y2partitioner/widgets/lvm_vg_bar_graph"
require "y2partitioner/widgets/lvm_vg_resize_button"
require "y2partitioner/widgets/device_buttons_set"
require "y2partitioner/widgets/columns"

module Y2Partitioner
  module Widgets
    module Pages
      # A Page for a LVM Volume Group. It contains several tabs.
      class LvmVg < Base
        # Constructor
        #
        # @param lvm_vg [Y2Storage::Lvm_vg]
        # @param pager [CWM::TreePager]
        def initialize(lvm_vg, pager)
          textdomain "storage"

          @lvm_vg = lvm_vg
          @pager = pager
          self.widget_id = "lvm_vg:" + lvm_vg.vg_name
        end

        # @return [Y2Storage::LvmVg] volume group the page is about
        def device
          @lvm_vg
        end

        # @macro seeAbstractWidget
        def label
          @lvm_vg.vg_name
        end

        # @macro seeCustomWidget
        def contents
          Top(
            VBox(
              Left(
                Tabs.new(
                  LvmVgTab.new(@lvm_vg, @pager),
                  LvmPvTab.new(@lvm_vg, @pager)
                )
              )
            )
          )
        end

        private

        # @return [String]
        def section
          Lvm.label
        end
      end

      # A Tab for the LVM logical volumes of a volume group
      class LvmVgTab < OverviewTab
        # @macro seeCustomWidget
        def contents
          return @contents if @contents

          device_buttons = DeviceButtonsSet.new(@pager)
          @contents = VBox(
            LvmVgBarGraph.new(device),
            table(device_buttons),
            Left(device_buttons)
          )
        end

        private

        # Returns a table with all logical volumes of a volume group, including
        # thin pools and thin volumes
        #
        # @see #devices
        #
        # @param buttons_set [DeviceButtonsSet]
        # @return [LvmDevicesTable]
        def table(buttons_set)
          table = LvmDevicesTable.new(devices, @pager, buttons_set)
          table.remove_columns(Columns::PeSize)
          table
        end

        # Returns all logical volumes of a volume group, including thin pools
        # and thin volumes
        #
        # @see Y2Storage::LvmVg#all_lvm_lvs
        #
        # @return [Array<Y2Storage::LvmLv>]
        def devices
          [
            BlkDevicesTable::DeviceTree.new(device, children: device.all_lvm_lvs)
          ]
        end
      end

      # A Tab for the LVM physical volumes of a volume group
      class LvmPvTab < CWM::Tab
        # Constructor
        #
        # @param lvm_vg [Y2Storage::Lvm_vg]
        # @param pager [CWM::TreePager]
        def initialize(lvm_vg, pager)
          textdomain "storage"

          @lvm_vg = lvm_vg
          @pager = pager
        end

        # @macro seeAbstractWidget
        def label
          _("&Physical Volumes")
        end

        # @macro seeCustomWidget
        def contents
          # Page wants a WidgetTerm, not an AbstractWidget
          @contents ||= VBox(
            table,
            Right(LvmVgResizeButton.new(device: @lvm_vg))
          )
        end

        private

        # Returns a table with all physical volumes of a volume group
        #
        # @return [ConfigurableBlkDevicesTable]
        def table
          return @table unless @table.nil?

          @table = ConfigurableBlkDevicesTable.new(devices, @pager)
          @table.show_columns(*columns)
          @table
        end

        def columns
          [
            Columns::Device,
            Columns::Size,
            Columns::Format,
            Columns::Encrypted,
            Columns::Type
          ]
        end

        def devices
          @lvm_vg.lvm_pvs.map(&:plain_blk_device)
        end
      end
    end
  end
end
