# Copyright (c) [2017-2019] SUSE LLC
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
require "cwm"
require "y2storage"

module Y2Partitioner
  module Widgets
    # Encrypted {Y2Storage::BlkDevice} password
    class EncryptPassword < CWM::CustomWidget
      # Constructor
      def initialize(controller)
        textdomain "storage"

        @controller = controller
        @checker = Y2Storage::EncryptPasswordChecker.new
      end

      # @macro seeAbstractWidget
      def help
        # help text for cryptofs
        _(
          "<p>\n" \
            "You will need to enter your encryption password.\n" \
          "</p>\n" \
          "<p>\n" \
            "If the encrypted file system does not contain any system file and therefore is\n" \
            "not needed for the update, you may select <b>Skip</b>. In this case, the\n" \
            "file system is not accessed during update.\n" \
          "</p>\n"
        )
      end

      # @macro seeAbstractWidget
      def validate
        msg = checker.error_msg(pw1, pw2)
        return true unless msg

        Yast::Report.Error(msg)
        Yast::UI.SetFocus(Id(:pw1))
        false
      end

      # @macro seeAbstractWidget
      def store
        @controller.encrypt_password = pw1
      end

      # @macro seeAbstractWidget
      def cleanup
        checker.tear_down
      end

      # @macro seeCustomWidget
      def contents
        Frame(
          Id(widget_id),
          _("Encryption Password"),
          MarginBox(
            1.45,
            0.5,
            VBox(
              Password(
                Id(:pw1),
                Opt(:hstretch),
                # Label: get password for user root
                # Please use newline if label is longer than 40 characters
                _("&Enter a Password for your File System:"),
                ""
              ),
              Password(
                Id(:pw2),
                Opt(:hstretch),
                # Label: get same password again for verification
                # Please use newline if label is longer than 40 characters
                _("Reenter the Password for &Verification:"),
                ""
              ),
              VSpacing(0.5)
            )
          )
        )
      end

      private

      # @return Y2Storage::EncryptPasswordChecker
      attr_reader :checker

      # @return [String]
      def pw1
        Yast::UI.QueryWidget(Id(:pw1), :Value)
      end

      # @return [String]
      def pw2
        Yast::UI.QueryWidget(Id(:pw2), :Value)
      end
    end
  end
end
