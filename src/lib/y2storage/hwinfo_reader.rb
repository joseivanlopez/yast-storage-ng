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

require "ostruct"
require "singleton"

module Y2Storage
  # Read hardware information for storage devices
  #
  # This class uses `hwinfo` to read hardware information from storage devices.
  # The information is read lazily for all devices at once and cached when the
  # #for_device method is called.
  #
  # The cache can be cleaned calling #reset.
  #
  # @example Get information for "/dev/sda"
  #   hwinfo = HWInfo.instance.for_device(name)
  #   hwinfo.driver #=> ["ahci", "sd"]
  #   hwinfo.device_file #=> "/dev/sda"
  #
  # @example Cleaning the cache
  #   HWInfo.instance.reset
  class HWInfoReader
    include Singleton

    # Return hardware info for the given device
    #
    # @param name [String] Device name (eg. "/dev/sda")
    # @return [OpenStruct] Hardware information
    def for_device(name)
      data[name]
    end

    # Reset the cache
    #
    # The values will be loaded when #for_device is called again.
    def reset
      @data = nil
    end

  private

    # Return devices information from hwinfo
    #
    # The information is cached. It can be cleaned by calling #reset.
    #
    # @return [Hash<String,OpenStruct>] Hardware information indexed by device name
    #
    # @see #data_from_hwinfo
    # @see #reset
    def data
      @data ||= data_from_hwinfo
    end

    # @return [Regexp] Regular expression to extract the 'bus' from the first line
    BUS_REGEXP = /\A\d+: (\w+) /

    # @return [Regexp] Regular expression to split hwinfo output
    DEVICE_REGEXP = /^(\d.+\n)/

    # Extract devices information from hwinfo
    #
    # @return [Hash<String,OpenStruct>] Hardware information indexed by device name
    def data_from_hwinfo
      output = Yast::Execute.on_target!("/usr/sbin/hwinfo", "--disk", "--listmd", stdout: :capture)

      lines = output.split(DEVICE_REGEXP).reject(&:empty?)

      lines.each_slice(2).each_with_object({}) do |(header, body), data|
        details = data_from_body(body)
        details.bus = header[BUS_REGEXP, 1]
        data[details.device_file] = details
      end
    end

    # @return [Array<String>] List of multi-valued properties
    MULTI_VALUED = ["driver", "driver_modules", "device_files"].freeze

    # Converts information from hwinfo to an OpenStruct
    #
    # By the way, it convers multi-valued properties to arrays.
    #
    # @return [OpenStruct] Sanitized hardware information
    def data_from_body(body)
      body.lines.map(&:strip).each_with_object(OpenStruct.new) do |line, data|
        key, value = line.split(":", 2)
        next if value.nil?
        key = key.downcase.tr(" ", "_").tr("()", "")
        value = value.tr("\"()", "").strip
        parsed_value = MULTI_VALUED.include?(key) ? parse_multi(value) : parse_single(value)
        data.public_send("#{key}=", parsed_value)
      end
    end

    # Sanitizes a single-value property
    #
    # @return [String] sanitized value
    def parse_single(value)
      value.strip
    end

    # Sanitizes a multi-value property
    #
    # @return [Array<String>] array containing all values
    def parse_multi(value)
      value.split(",").map(&:strip)
    end
  end
end