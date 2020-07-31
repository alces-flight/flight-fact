#==============================================================================
# Copyright (C) 2020-present Alces Flight Ltd.
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
# https://github.com/alces-flight/alces-flight/flight-fact
#==============================================================================

require 'tty-prompt'
require_relative '../config_updater'

module FlightFact
  module Commands
    class Configure < Command
      # def run
      #   # TODO: The configure command is currently broken and needs to be reworked
      #   raise NotImplementedError

      #   process_jwt_option
      #   process_asset_option

      #   if $stdout.tty?
      #     prompt_for_jwt
      #     prompt_for_default_asset
      #     opts.validate = prompt.yes?('Validate credentials?') unless opts.validate
      #   end

      #   # Reset the credentials with a copy of the original
      #   @credentials = CredentialsConfig.new(credentials.to_h)

      #   validate if opts.validate && credentials.resolve_asset_id
      #   save_credentials
      # end

      def run
        if $stdout.tty? && opts.select { |_, v| v }.empty?
          # Run interactively if connected to a TTY without options
          run_interactive
        else
          # Run non interactively
          run_non_interactive
        end
      end

      def run_interactive
        raise NotImplementedError
      end

      def run_non_interactive
        if opts.jwt && opts.jwt.empty?
          updater.jwt = nil
        elsif opts.jwt
          updater.jwt = opts.jwt
        else
          updater.jwt = credentials.jwt
        end

        if opts.asset && opts.asset.empty?
          updater.asset_id = nil
        elsif opts.asset && opts.id
          updater.asset_id = opts.asset
        elsif opts.asset
          updater.asset_name = opts.asset
        elsif Config::CACHE.implicit_static_asset?
          updater.asset_name = Config::CACHE.unresolved_asset_name
        elsif Config::CACHE.static_asset?
          updater.asset_id = Config::CACHE.static_asset_id
        else
          updater.asset_id = nil
        end

        updater.validate if opts.validate

        updater.save
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def updater
        @updater ||= ConfigUpdater.new.tap(&:assert_writable)
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

      def mask(jwt)
        return nil if jwt.nil?
        return ('*' * jwt.length) if jwt[-8..-1].nil?
        ('*' * 24) + jwt[-8..-1]
      end
    end
  end
end

