#==============================================================================
# Copyright (C) 2019-present Alces Flight Ltd.
#
# This file is part of Flight Asset.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Asset is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Asset. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Asset, please visit:
# https://github.com/alces-flight/alces-flight/flight-asset-cli
#==============================================================================

require 'tty-prompt'

module FlightFact
  module Commands
    class Configure < Command
      def run
        process_jwt_option
        process_asset_option

        if $stdout.tty?
          prompt_for_jwt
          prompt_for_default_asset
          opts.validate = prompt.yes?('Validate credentials?') unless opts.validate
        end

        validate if opts.validate
        save_credentials
      end

      def process_jwt_option
        return unless opts.jwt
        if opts.jwt.empty?
          credentials.jwt = nil
        else
          credentials.jwt = opts.jwt
        end
      end

      def process_asset_option
        return unless opts.asset
        if opts.asset.empty?
          credentials.asset_id = nil
          credentials.unresolved_name = nil
        elsif opts.asset && opts.id
          credentials.asset_id = opts.asset
          credentials.unresolved_name = nil
        else
          credentials.asset_id = nil
          credentials.unresolved_name = opts.asset
        end
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def prompt_for_jwt
        old_jwt_mask = mask(credentials.jwt)
        opts = { required: true }.tap { |o| o[:default] = old_jwt_mask if credentials.jwt }
        new_jwt = prompt.ask 'Flight Center API token:', **opts
        credentials.jwt = new_jwt unless new_jwt == old_jwt_mask
      end

      def prompt_for_default_asset
        if prompt.yes? "Define the default asset by ID?", default: (credentials.asset_id ? true : false)
          opts = { requried: true }.tap do |o|
            o[:default] = credentials.asset_id if credentials.asset_id
          end
          credentials.asset_id = prompt.ask 'Default Asset ID:', **opts
          credentials.unresolved_name = nil
        elsif prompt.yes? "Define the default asset by name?", default: true
          name = prompt.ask "Default Asset Name:", default: default_to_asset_prompt
          credentials.unresolved_name = name
          credentials.asset_id = nil
        elsif credentials.asset_id
          $stderr.puts 'Removing previously set default asset'
          credentials.asset_id = nil
          credentials.unresolved_name = nil
        end
      end

      def default_to_asset_prompt
        credentials.unresolved_name || `hostname --short`.chomp
      end

      # NOTE: This validation could fail for rather complex reasons. The request
      # to `flight asset` uses a different set of configurations which opens the
      # possibility for inconsistencies (e.g. base_url, expired tokens etc..)
      def validate
        # Reset to a new credentials object
        @credentials = CredentialsConfig.new(credentials.to_h)
        request_fact
      rescue InternalError
        raise InputError, <<~ERROR.chomp
          Could not locate the asset! Please check the following:
           * Ensure the asset exists, and
           * Regenerate the API token as it may have expired.

          Please contact your system administrator if this error persists
        ERROR
      end

      def mask(jwt)
        return nil if jwt.nil?
        return ('*' * jwt.length) if jwt[-8..-1].nil?
        ('*' * 24) + jwt[-8..-1]
      end
    end
  end
end

