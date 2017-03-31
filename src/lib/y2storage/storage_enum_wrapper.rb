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

require "storage"

module Y2Storage
  # Mixin that enables a class to become a wrap around one of the enums
  # provided by the libstorage Ruby bindings.
  #
  # In Ruby, usage of full-fledged objects is more convenient than direct usage
  # of enums. This mixin makes possible to define new classes that serve as an
  # object oriented interface to certain enums, adding extra methods as needed.
  #
  # A class can include this mixing and then use the wrap_enum macro to point to
  # the name of the enum. That will automatically add methods to fetch all the
  # possible values, to compare them, etc. It will also add a constant for every
  # possible value. Last but not least, the mixin also ensures compatibility
  # with the mechanisms used by StorageClassWrapper, making sure objects are
  # properly translated before being forwarded to the Storage namespace.
  #
  # @see StorageClassWrapper
  module StorageEnumWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Constructor for the wrapper object
    #
    # @param value [Fixnum, #to_s] integer representation or name of the
    #   concrete enum value
    def initialize(value)
      if value.is_a?(::Fixnum)
        @storage_value = value
      else
        @storage_value = Storage.const_get("#{self.class.storage_enum}_#{value.to_s.upcase}")
      end
    end

    # Equivalent to this object in the Storage world, i.e. the numeric value
    def to_storage_value
      @storage_value
    end

    def to_i
      to_storage_value
    end

    def to_sym
      self.class.value_to_sym(to_storage_value)
    end

    def to_s
      to_sym.to_s
    end

    # Checks whether the object corresponds to the given enum value. Initially
    # checking by name, this method is expected to be extended by the particular
    # classes to add more semantic checks if needed.
    #
    # By default, this will be the base comparison used in the case statements.
    #
    # @param name [#to_sym]
    # @return [Boolean]
    def is?(name)
      to_sym == name.to_sym
    end

    def ==(other)
      other.class == self.class && other.to_storage_value == to_storage_value
    end

    alias_method :eql?, :==

    def ===(other)
      other.class == self.class && is?(other)
    end

    # Class methods to be added
    module ClassMethods
      # Macro to define the enum in the Storage namespace to be wrapped.
      #
      # It automatically checks all the possible values defined for that enum in
      # the Storage namespace and creates corresponding constants in the class.
      # See example below.
      #
      # @param storage_enum [String] common part of the enum name
      #
      # @example Basic usage of wrap_enum
      #
      #   module Y2Storage
      #     class PartitionType
      #       include StorageEnumWrapper
      #       wrap_enum "PartitionType"
      #     end
      #   end
      #
      #   Y2Storage::PartitionType.all.each do |type|
      #     puts "Name: #{type.to_s} -> Internal libstorage value: #{type.to_i}"
      #   end
      #
      #   pri1 = Y2Storage::PartitionType.find(:primary)
      #   pri2 = Y2Storage::PartitionType::PRIMARY
      #   pri3 = Y2Storage::PartitionType.find(Storage::PartitionType_PRIMARY)
      #   pri1 == pri2 # => true
      #   pri1 == pri3 # => true
      #   pri1.is?(:primary) # => true
      #   pri2.to_sym # => :primary
      def wrap_enum(storage_enum)
        @storage_enum = storage_enum
        @storage_symbols = {}

        constants = Storage.constants.select { |c| c.to_s.start_with?("#{storage_enum}_") }
        constants.each do |constant_name|
          value = Storage.const_get(constant_name)
          name = constant_name.to_s.sub(/#{storage_enum}_/, "")

          @storage_symbols[value] = name.downcase.to_sym
          const_set(name, new(value))
        end
      end

      # Returns an object for every one of the possible enum values
      #
      # @return [Array]
      def all
        @storage_symbols.keys.sort.map { |storage_value| new(storage_value) }
      end

      # Returns an object representing the enum, fetched by label or numeric
      # value
      def find(name_or_value)
        new(name_or_value)
      end

      def storage_enum
        @storage_enum
      end

      def value_to_sym(value)
        @storage_symbols[value]
      end
    end
  end
end
