#!/usr/bin/env ruby
#
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

require "yast"
require "y2storage"
require "y2storage/actions_presenter"
require "installation/proposal_client"

Yast.import "Popup"

module Y2Storage
  module Clients
    # Proposal client to show the list of storage actions
    class PartitionsProposal < ::Installation::ProposalClient
      include Yast::Logger

      def self.state(storage_manager)
        return if staging_revision == storage_manager.staging_revision

        self.staging_revision = storage_manager.staging_revision

        staging = storage_manager.y2storage_staging
        actiongraph = staging ? staging.actiongraph : nil
        self.actions_presenter = ActionsPresenter.new(actiongraph)
      end

      def initialize
        create_proposal
        self.class.state(storage_manager)
      end

      def make_proposal(_attrs)
        {
          "preformatted_proposal" => actions_presenter.to_html,
          "links"                 => actions_presenter.events,
          "language_changed"      => false
        }
      end

      def ask_user(param)
        event = param["chosen_id"]

        if actions_presenter.events.include?(event)
          actions_presenter.update_status(event)
          result = :again
        else
          Yast::Report.Warning(_("This action is not enabled at this moment"))
          result = :back
        end

        { "workflow_sequence" => result }
      end

      def description
        {
          "id"              => "partitions",
          "rich_text_title" => _("Partitioning"),
          "menu_title"      => _("&Partitioning")
        }
      end

    private

      class << self
        attr_accessor :staging_revision
        attr_accessor :actions_presenter
      end

      def actions_presenter
        self.class.actions_presenter
      end

      def staging_revision
        self.class.staging_revision
      end

      def storage_manager
        StorageManager.instance
      end

      def create_proposal
        proposal = storage_manager.proposal || new_proposal
        proposal.propose if !proposal.proposed?
        storage_manager.proposal = proposal if storage_manager.proposal.nil?
      rescue Y2Storage::Proposal::Error
        log.error("generating proposal failed")
      end

      def new_proposal
        settings = ProposalSettings.new_for_current_product
        probed = storage_manager.y2storage_probed
        disk_analyzer = storage_manager.probed_disk_analyzer
        Proposal.new(settings: settings, devicegraph: probed, disk_analyzer: disk_analyzer)
      end
    end
  end
end