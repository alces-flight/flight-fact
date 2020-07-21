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
        if options_provided?
          raise NotImplementedError
        elsif $stdout.tty?
          run_prompts
        else
          $stderr.puts 'Nothing to do...'
        end
      end

      def options_provided?
        !opts.select { |_, v| v }.empty?
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def run_prompts
        prompt_for_jwt
        prompt_for_default_asset
        validate if prompt.yes?('Validate credentials?', default: false)
        save_credentials
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
          name = prompt.ask "Default Asset Name:", default: `hostname --short`.chomp
          credentials.unresolved_name = name
          credentials.asset_id = nil
        elsif credentials.asset_id
          $stderr.puts 'Removing previously set default asset'
          credentials.asset_id = nil
          credentials.unresolved_name = nil
        end
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

