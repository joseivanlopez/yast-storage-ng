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

require "y2storage/storage_class_wrapper"
require "y2storage/partitionable"
require "y2storage/md_level"
require "y2storage/md_parity"

module Y2Storage
  # A MD RAID
  #
  # This is a wrapper for Storage::Md
  #
  # @note Some BIOS RAIDs (IMSM and DDF) can be handled by mdadm as MD RAIDs,
  #   see {MdContainer} and {MdMember} subclasses.
  class Md < Partitionable
    wrap_class Storage::Md, downcast_to: ["MdMember", "MdContainer"]

    # @!method self.create(devicegraph, name)
    #   @param devicegraph [Devicegraph]
    #   @param name [String] name of the new device, like "/dev/md0",
    #     "/dev/md/foo" or "/dev/md/1"
    #   @return [Md]
    storage_class_forward :create, as: "Md"

    # @!method devices
    #   Block devices used by the MD RAID, in no particular order
    #
    #   @note This returns an array based on the underlying SWIG vector,
    #   modifying the returned object will have no effect in the Md object.
    #   To modify the list of devices in the MD array, check other methods like
    #   {#add_device} or {#remove_device}.
    #
    #   @return [Array<BlkDevice>]
    storage_forward :devices, as: "BlkDevice"

    # @!method add_device(blk_device)
    #   Adds a block device to the MD RAID.
    #
    #   The device is added in an undefined position, but the holder object is
    #   returned, so the caller can enforce the position (or any other of the
    #   properties defined by the libstorage-ng holder) after the operation.
    #
    #   @param blk_device [BlkDevice]
    #   @return [Storage::MdUser]
    storage_forward :add_device, raise_errors: true

    # @!method remove_device(blk_device)
    #   Removes a block device from the MD RAID.
    #
    #   @param blk_device [BlkDevice]
    storage_forward :remove_device, raise_errors: true

    # @!method numeric?
    #   @return [Boolean] whether the MD RAID has a numeric name
    storage_forward :numeric?

    # @!method number
    #   @return [Integer] the number of the MD RAID.
    storage_forward :number

    # @!attribute md_level
    #   RAID level of the MD RAID.
    #   @return [MdLevel]
    storage_forward :md_level, as: "MdLevel"
    storage_forward :md_level=

    # @!attribute md_parity
    #   Parity of the MD RAID.
    #   @return [MdParity]
    storage_forward :md_parity, as: "MdParity"
    storage_forward :md_parity=

    # @!attribute chunk_size
    #   Chunk size of the MD RAID.
    #   @return [DiskSize]
    storage_forward :chunk_size, as: "DiskSize"
    storage_forward :chunk_size=

    # @!attribute uuid
    #   @return [String] the UUID of the MD RAID.
    storage_forward :uuid

    # @!attribute metadata
    #   @return [String] metadata format of the MD RAID, e.g. "1.0" or "imsm".
    storage_forward :metadata

    # @!method in_etc_mdadm?
    #   @return [Boolean] whether the MD RAID is included in /etc/mdadm.conf
    storage_forward :in_etc_mdadm?

    # @!method in_etc_mdadm=(value)
    #   @see #in_etc_mdadm?
    #   @param value [Boolean]
    storage_forward :in_etc_mdadm=

    # @!method minimal_number_of_devices
    #   Minimal number of devices required by the RAID.
    #
    #   For RAIDs of level CONTAINER it returns 0 (those RAIDs cannot be created
    #   or modified anyway).
    #
    #   @return [Integer]
    storage_forward :minimal_number_of_devices

    # @!method self.all(devicegraph)
    #   @param devicegraph [Devicegraph]
    #   @return [Array<Md>] all the mds in the given devicegraph
    storage_class_forward :all, as: "Md"

    # @!method self.find_by_name(devicegraph, name)
    #   @param devicegraph [Devicegraph]
    #   @param name [String] kernel-style device name (e.g. "/dev/md0" or /dev/md/test)
    #   @return [Md] nil if there is no such md
    storage_class_forward :find_by_name, as: "Md"

    # @!method self.find_free_numeric_name(devicegraph)
    #   @param devicegraph [Devicegraph]
    #   @return [String] next free numeric name for a MD RAID
    storage_class_forward :find_free_numeric_name

    def inspect
      md_class = self.class.name.split("::").last
      "<#{md_class} #{name} #{size} #{md_level}>"
    end

    # Whether the RAID is defined by software
    #
    # This method is used to distinguish between Software RAID and BIOS RAID,
    # see {Devicegraph#bios_raids} and {Devicegraph#software_raids}.
    #
    # All RAID classes should define this method, see {DmRaid#software_defined?},
    # {MdContainer#software_defined?} and {MdMember#software_defined?}.
    #
    # @note MD RAIDS are considered defined by sofware.
    #
    # @return [Boolean] true
    def software_defined?
      true
    end

    # Default partition table type for newly created partition tables
    # @see Partitionable#preferred_ptable_type
    #
    # @return [PartitionTables::Type]
    def preferred_ptable_type
      # We always suggest GPT
      PartitionTables::Type.find(:gpt)
    end

    # Raw (non encrypted) versions of the devices included in the MD array.
    #
    # If none of the devices is encrypted, this is equivalent to #devices,
    # otherwise it returns the original devices instead of the encryption ones.
    #
    # @return [Array<BlkDevice>]
    def plain_devices
      devices.map(&:plain_device)
    end

    # Block devices used in the MD array, sorted according to its position in
    # the RAID.
    #
    # @see #devices for an unsorted version of this
    #
    # To know more about why order of devices is relevant, check fate#313521.
    #
    # @note This returns an array based on the underlying SWIG structure,
    # modifying the returned object will have no effect in the Md object.
    # To modify the list of devices in the MD array, check other methods like
    # {#sorted_devices=}, {#push_device}, {#add_device} or {#remove_device}.
    #
    # @note libstorage-ng considers that a device with a sort-key of 0 has no
    # specific position in the list. Such devices are listed at the beginning of
    # the list by this method.
    #
    # @note Take into account that this method returns a mix of RAID devices and
    # spare devices, since {#devices} makes no difference between both.
    #
    # @return [Array<BlkDevice>]
    def sorted_devices
      md_users.sort_by(&:sort_key).map { |holder| Y2Storage::Device.downcasted_new(holder.source) }
    end

    # Raw (non encrypted) versions of the devices included in the MD array,
    # sorted according to the position of the devices in the RAID.
    #
    # If none of the devices is encrypted, this is equivalent to #sorted_devices,
    # otherwise it returns the original devices instead of the encryption ones.
    #
    # @return [Array<BlkDevice>]
    def sorted_plain_devices
      sorted_devices.map(&:plain_device)
    end

    # Updates the sorted list of devices in the array.
    #
    # Devices that are not currently in the RAID will be added, those that are
    # in the RAID but not in the passed list will be removed and, finally, order
    # will be forced to match the passed list.
    #
    # @note If the RAID already exists in the system, libstorage-ng cannot alter
    # the list of devices or reorder them. In such scenario, only removing
    # faulty devices or modifying the list of spare ones is possible. Thus,
    # never call this method on a Md device that already exists in the real
    # system or the commit operation will likely fail.
    #
    # @see #sorted_devices
    #
    # @param devs_list [Array<BlkDevice>]
    def sorted_devices=(devs_list)
      deleted = devices - devs_list
      deleted.each { |dev| remove_device(dev) }

      added = devs_list - devices
      added.each { |dev| add_device(dev) }

      md_users.each do |holder|
        index = devs_list.index { |dev| dev.sid == holder.source_sid }
        holder.sort_key = index + 1
      end
    end

    # Adds a device to the RAID as the last one in the list of sorted devices.
    #
    # @see #add_device
    # @see #sorted_devices
    #
    # @param device [BlkDevice]
    def push_device(device)
      holder = add_device(device)
      holder.sort_key = md_users.map(&:sort_key).max + 1
    end

    # Name of the named RAID, if any
    #
    # @return [String, nil] nil if this is not a named array
    def md_name
      return nil if numeric?
      basename
    end

    # Sets the name, effectively turning the device into a named array
    #
    # @note: Only works if the array does not exist yet in the system. Cannot be
    #   used to rename in-disk arrays.
    # @note: Trying to 'unset' the name does not turn the array back into a
    #   numeric one, it raises an exception instead.
    # @note: Is actually possible to set the array to numeric again assigning
    #   the name to mdX where X is a correct (available) number, but that
    #   behavior is not granted to work in the future.
    def md_name=(new_name)
      if new_name.nil? || new_name.empty?
        raise ArgumentError, "Resetting the name back to numeric is not supported"
      end
      self.name = "/dev/md/#{new_name}"
    end

  protected

    # Holders connecting the MD Raid to its component block devices in the
    # devicegraph.
    #
    # Direct access to these objects is needed to control the sorting of the
    # devices or to identify devices marked as spare or faulty.
    #
    # @return [Array<Storage::MdUser>]
    def md_users
      to_storage_value.in_holders.to_a.map { |h| Storage.to_md_user(h) }
    end

    def types_for_is
      types = super
      types << :md
      # All Software RAIDs are Md devices, but MdMember derived class represents
      # BIOS RAIDs. Class MdContainer is also derived from Md, but objects of this
      # class are not be considered neither Software nor BIOS RAIDs.
      # To properly exclude MdContainer as :raid device, here only Software RAIDs
      # are considered to be raid type.
      types << :raid if software_defined?
      types << :software_raid if software_defined?
      types
    end
  end
end
