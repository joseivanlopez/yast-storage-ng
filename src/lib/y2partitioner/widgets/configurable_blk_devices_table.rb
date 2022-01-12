# Copyright (c) [2017-2021] SUSE LLC
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

require "yast"
require "cwm/table"

require "y2partitioner/device_graphs"
require "y2partitioner/ui_state"
require "y2partitioner/widgets/blk_devices_table"
require "y2partitioner/widgets/columns"
require "y2partitioner/dialogs/device_description"

module Y2Partitioner
  module Widgets
    # Table widget to represent a given list of devices in one of the
    # the main screens of the partitioner
    class ConfigurableBlkDevicesTable < BlkDevicesTable
      include Yast::I18n

      # Constructor
      #
      # @param entries [Array<DeviceTableEntry>]
      # @param pager [CWM::TreePager]
      # @param buttons_set [DeviceButtonsSet]
      def initialize(entries, pager, buttons_set = nil)
        super()
        textdomain "storage"

        @entries = entries
        @pager = pager
        @buttons_set = buttons_set
      end

      # @macro seeAbstractWidget
      def opt
        [:notify, :immediate]
      end

      def contents
        return @contents if @contents

        # Before calculating the content, ensure consistency of #open_items
        # FIXME: the API to fetch the stored state may change, see the comment in UIState#extra
        self.open_items = UIState.instance.extra&.fetch(widget_id, nil)
        @contents = super
      end

      # @macro seeAbstractWidget
      def init
        return if devices.empty? # do nothing if there is nothing in table

        # Now that the content has been displayed, invalidate its memoization to ensure #open_items
        # is updated in the next UI draw with the information from UIState
        @contents = nil

        self.value = initial_entry.row_id
        handle_selected
      end

      # @macro seeAbstractWidget
      def handle(event)
        case event["EventReason"]
        when "SelectionChanged"
          handle_selected
        when "Activated"
          handle_activated
        end
      end

      # Handles the event generated by the user changing the selected row
      #
      # If a buttons set was provided in the constructor, this updates the set
      # to reflect the currently selected device.
      def handle_selected
        dev = selected_device

        return nil unless dev

        UIState.instance.select_row(dev.sid)
        buttons_set.device = dev if buttons_set

        nil
      end

      # Handles the event generated by the user double clicking on a row (or pressing Enter in ncurses)
      #
      # It jumps to the page associated to the selected device or shows a description popup when the
      # current page is already a page associated to a device.
      def handle_activated
        device = selected_device

        return nil unless device

        if pager.device_page?
          Dialogs::DeviceDescription.new(device).run

          return nil
        end

        jump_to_page(device)
      end

      # Device object selected in the table
      #
      # @return [Y2Storage::Device, nil] nil if anything is selected
      def selected_device
        return nil if items.empty? || !value

        sid = value[/.*:(.*)/, 1].to_i
        device_graph.find_device(sid)
      end

      # Adds new columns to show in the table
      #
      # @note When a column :column_name is added, the methods #column_name_title
      #   and #column_name_value should exist.
      #
      # @param column_names [*Symbol]
      def add_columns(*column_names)
        columns.concat(column_names)
      end

      # Avoids to show some columns in the table
      #
      # @param column_names [*Symbol]
      def remove_columns(*column_names)
        column_names.each { |c| columns.delete(c) }
      end

      # Fixes a set of specific columns to show in the table
      #
      # @param column_names [*Symbol]
      def show_columns(*column_names)
        @columns = column_names
      end

      # @macro seeAbstractWidget
      # @see #columns_help
      def help
        _("<p>The table contains the following columns:</p>") + columns_help
      end

      private

      # @return [DeviceButtonsSet] optional buttons set that must be
      #   updated when the user changes the selection in the table
      attr_reader :buttons_set

      # @return [CWM::TreePager] general pager used to navigate through the Partitioner
      attr_reader :pager

      # @return [Array<DeviceTableEntry>] list of device entries to display
      attr_reader :entries

      DEFAULT_COLUMNS = [
        Columns::Device,
        Columns::Size,
        Columns::Format,
        Columns::Encrypted,
        Columns::Type,
        Columns::FilesystemLabel,
        Columns::MountPoint,
        Columns::RegionStart,
        Columns::RegionEnd
      ].freeze

      def device_graph
        DeviceGraphs.instance.current
      end

      def columns
        @columns ||= default_columns.dup
      end

      def default_columns
        DEFAULT_COLUMNS
      end

      # @see BlkDevicesTable#open_by_default?
      #
      # @param entry [DeviceTableEntry]
      # @return [Boolean]
      def open_by_default?(entry)
        return true unless entry_with_subvols?(entry)

        entry.children.none? { |c| c.device.snapshot? }
      end

      # Whether the children of the given entry are Btrfs subvolumes
      #
      # @return [Boolean]
      def entry_with_subvols?(entry)
        # We never mix subvolumes and other kind of devices in the same level of
        # a branch, so checking the first child is enough
        child = entry.children.first
        return false unless child

        child.device.is?(:btrfs_subvolume)
      end

      # Table entry to select initially when the table is rendered
      #
      # @see #init
      #
      # @return [DeviceTableEntry, nil]
      def initial_entry
        initial_sid = UIState.instance.row_id
        @initial_entry = entry(initial_sid)

        # After adding a new Btrfs, it may happen that such device is not represented in
        # the table as a separate entry, but only through its block device
        @initial_entry ||= fs_blk_device_entry(initial_sid)

        # If we do not have a valid sid, then pick the first available device.
        # Done to allow e.g. chain of delete like described in bsc#1076318,
        # although this is very likely not longer necessary after many changes in the
        # Partitioner and in the libyui tables
        @initial_entry ||= entries.first
      end

      # Given the sid of a single (no multidevice) filesystem, returns the table
      # entry of its block device
      #
      # @param sid [Integer]
      # @return [DeviceTableEntry, nil] nil if the sid does not correspond to a single
      #   filesystem or if the corresponding block device is not in the table
      def fs_blk_device_entry(sid)
        return nil unless sid

        device = device_graph.find_device(sid.to_i)
        return nil unless device&.is?(:blk_filesystem)
        return nil if device.multidevice?

        entry(device.plain_blk_devices.first.sid)
      end

      # Switches to the page of the specified device, if possible
      #
      # If the target page exists, it updates all the corresponding state information
      # before doing the real switch.
      def jump_to_page(device)
        page = device_page(device)

        return nil unless page

        state = UIState.instance

        # First, save the status of the current page
        state.save_extra_info

        # Then, pretend the user visited the new page and then select the device
        state.select_page(page.tree_path)
        state.select_row(device.sid)

        pager.handle("ID" => page.widget_id)
      end

      # Finds a page associated to the given device
      #
      # When there is no page for the given device, it tries to find a page associated to the device of
      # the parent table entries.
      #
      # @param device [Y2Storage::Device]
      # @return [CWM::Page, nil]
      def device_page(device)
        page = pager.device_page(device)
        return page if page

        device = holding_device(device)
        return nil unless device

        device_page(device)
      end

      # Device associated to the parent table entry of the given device
      #
      # @param device [Y2Storage::Device]
      # @return [Y2Storage::Device, nil]
      def holding_device(device)
        parent_entry = parent_entry(entry(device))
        parent_entry&.device
      end

      # Parent table entry of the given one
      #
      # @param entry [DeviceTableEntry]
      # @return [DeviceTableEntry, nil]
      def parent_entry(entry)
        entries.flat_map(&:all_entries).find { |e| e.parent?(entry) }
      end
    end
  end
end
