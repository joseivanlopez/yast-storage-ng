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

require "y2storage/proposal/initial_strategies/base"

module Y2Storage
  module Proposal
    module InitialStrategies
      # Class to calculate a storage proposal to install the system
      class Ng < Base
        class << self
          # Calculates the initial proposal
          #
          # If a proposal is not possible by honoring current settings, other settings
          # are tried. For example, a proposal without separate home or without snapshots
          # will be calculated.
          #
          # @see GuidedProposal#initialize
          #
          # @param settings [ProposalSettings] if nil, default settings will be used
          # @param devicegraph [Devicegraph] starting point. If nil, the probed
          #   devicegraph will be used
          # @param disk_analyzer [DiskAnalyzer] if nil, a new one will be created
          #   based on the initial devicegraph.
          #
          # @return [GuidedProposal]
          def initial_proposal(settings: nil, devicegraph: nil, disk_analyzer: nil)
            # Try proposal with initial settings
            current_settings = settings || ProposalSettings.new_for_current_product
            log.info("Trying proposal with initial settings: #{current_settings}")
            proposal = try_proposal(current_settings.dup, devicegraph, disk_analyzer)

            loop do
              volume = first_configurable_volume(current_settings)

              return proposal if !proposal.failed? || volume.nil?

              # Try again after disabling 'adjust_by_ram'
              if proposal.failed? && adjust_by_ram_active_and_configurable?(volume)
                volume.adjust_by_ram = false
                log.info("Trying proposal after disabling 'adjust_by_ram' for '#{volume.mount_point}'")
                proposal = try_proposal(current_settings.dup, devicegraph, disk_analyzer)
              end

              # Try again after disabling 'snapshots'
              if proposal.failed? && snapshots_active_and_configurable?(volume)
                volume.snapshots = false
                log.info("Trying proposal after disabling 'snapshots' for '#{volume.mount_point}'")
                proposal = try_proposal(current_settings.dup, devicegraph, disk_analyzer)
              end

              # Try again after disabling the volume
              if proposal.failed? && proposed_active_and_configurable?(volume)
                volume.proposed = false
                log.info("Trying proposal after disabling '#{volume.mount_point}'")
                proposal = try_proposal(current_settings.dup, devicegraph, disk_analyzer)
              end
            end
          end

        private

          def first_configurable_volume(settings)
            volumes = settings.volumes.select { |v| configurable_volume?(v) }
            volumes.sort_by(&:disable_order).first
          end

          def configurable_volume?(volume)
            volume.proposed? && (
              adjust_by_ram_active_and_configurable?(volume) ||
              snapshots_active_and_configurable?(volume))
          end

          def proposed_active_and_configurable?(volume)
            active_and_configurable?(volume, :proposed)
          end

          def adjust_by_ram_active_and_configurable?(volume)
            active_and_configurable?(volume, :adjust_by_ram)
          end

          def snapshots_active_and_configurable?(volume)
            return false unless volume.fs_type.is?(:btrfs)
            active_and_configurable?(volume, :snapshots)
          end

          def active_and_configurable?(volume, attr)
            volume.send(attr) && volume.send("#{attr}_configurable")
          end
        end
      end
    end
  end
end
