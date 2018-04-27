# encoding: utf-8

# Copyright (c) [2018] SUSE LLC
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
require "abstract_method"

module Y2Partitioner
  module Widgets
    # Abstract class to unify the definition of table widgets used to
    # represent collections of block devices.
    #
    # The subclasses must define the following methods:
    #
    #   * #columns returning an array of symbols
    #   * #devices returning a collection of {Y2Storage::BlkDevice}
    class Table < CWM::Table
      attr_reader :records

      abstract_method :columns

      def initialize(records)
        textdomain "storage"

        @records = records
      end

      # @see CWM::Table#header
      def header
        columns.map { |c| send("#{c}_title") }
      end

      # @see CWM::Table#items
      def items
        records.map { |r| values_for(r) }
      end

      # Updates table content
      def refresh
        change_items(items)
      end

      # Builds the help, including columns help
      def help
        _("<p>The table contains:</p>") + columns_help
      end

    private

      # LibYUI id for the row used to represent a device
      #
      # @param record
      def row_id(record)
        id = records.index(record) + 1

        "table:record:#{id}"
      end

      def values_for(record)
        [row_id(record)] + columns.map { |c| send("#{c}_value", record) }
      end

      def columns_help
        columns.map { |c| column_help(c) }.join("\n")
      end

      def column_help(column)
        help_method = "#{column}_help"
        return nil unless respond_to?(help_method, true)

        send(help_method)
      end
    end
  end
end
