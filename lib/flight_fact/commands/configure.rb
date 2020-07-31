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
      class Updater
        extend Forwardable
        attr_reader :asset_name, :asset_id
        def_delegators :credentials, :jwt, :jwt=

        def asset_id=(id)
          @asset_name = nil
          @asset_id = id
        end

        def asset_name=(name)
          @asset_name = name
          # Attempts to resolve the asset name
          @asset_id = Config::CACHE.fetch_asset_id_by_name(name)
        rescue
          # Logs the asset name wasn't resolve but flags the asset_id as truthy
          # This will trigger the name to be resolved at some future point - hopefully
          @asset_id = true
          Config::CACHE.logger.error <<~ERROR.chomp.chomp
            Failed to resolve asset: #{name}. Continuing with an unresolved asset name.
          ERROR
        end

        def credentials
          @credentials ||= Config::CACHE.load_credentials
        end

        ##
        # Saves both the credentials file and updated config
        def save
          # Ensures the user has permission to preform the update
          assert_writable

          # Update the main config
          Config::CACHE.static_asset_id = asset_id
          Config::CACHE.unresolved_asset_name = asset_name

          # Reject saving the default values
          blank = Config.new.to_h
          data = Config::CACHE.to_h.reject { |k, v| blank[k] == v }.to_h
          Config::CACHE.logger.info "Updating: #{CONFIG_PATH}"
          File.write CONFIG_PATH, YAML.dump(data)

          # Update the credentials
          Config::CACHE.logger.info "Updating: #{Config::CACHE.credentials_path}"
          File.write Config::CACHE.credentials_path, YAML.dump(credentials.to_h)
        end

        ##
        # Checks the user has permission to preform the update on both the
        # main config and credentials config. This is to prevent partial
        # updates. The results is cached to prevent it rerunning needlessly
        def assert_writable
          @assert_writable ||= begin
            [CONFIG_PATH, Config::CACHE.credentials_path].each do |path|
              raise PermissionError, <<~ERROR.chomp unless writable?(path)
                You do not have permission to update the following config: #{path}
              ERROR
            end
            true
          end
        end

        ##
        # Use to detect if the user can write to a particular path, either by:
        # * Writing the existing content back to the file, or
        # * Touching a blank file if missing
        def writable?(path)
          if File.exists? path
            File.write path, File.read(path)
          else
            FileUtils.mkdir_p File.dirname(path)
            FileUtils.touch path
            FileUtils.rm path
          end
          true
        rescue
          false
        end
      end

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

        updater.save
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def updater
        @updater ||= Updater.new.tap(&:assert_writable)
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

