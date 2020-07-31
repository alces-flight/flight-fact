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

module FlightFact
  class ConfigUpdater
    extend Forwardable
    attr_reader :asset_name, :asset_id, :credentials
    def_delegators :credentials, :jwt, :jwt=

    ##
    # Sets the asset_name/asset_id based on the initial values
    def initialize
      if Config::CACHE.implicit_static_asset?
        self.asset_name = Config::CACHE.unresolved_asset_name
      elsif Config::CACHE.static_asset?
        self.asset_id = Config::CACHE.static_asset_id
      end
      @credentials ||= Config::CACHE.load_credentials
    end

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

    ##
    # Saves both the credentials file and updated config
    def save
      # Ensures the user has permission to preform the update
      assert_writable

      # Update the main config
      Config::CACHE.static_asset_id = asset_id
      if asset_name.nil? # Do not save nil names
        Config::CACHE.delete(:unresolved_asset_name)
      else
        Config::CACHE.unresolved_asset_name = asset_name
      end

      # Reject saving the default values
      blank = Config.new.to_h
      data = Config::CACHE.to_h.reject { |k, v| blank[k] == v }
      Config::CACHE.logger.info "Updating: #{CONFIG_PATH}"
      File.write CONFIG_PATH, YAML.dump(data)

      # Update the credentials
      Config::CACHE.logger.info "Updating: #{Config::CACHE.credentials_path}"
      credentials.delete(:jwt) if jwt.nil?
      File.write Config::CACHE.credentials_path, YAML.dump(credentials.to_h)
    end

    def validate
      if asset_id == true
        raise ValidationError, <<~ERROR.chomp
          Could not locate the specified asset!
          Please ensure the following executes correctly and try again:
          #{Paint["#{Config::CACHE.asset_command} show #{asset_name}", :yellow]}
        ERROR
      elsif asset_id
        begin
          credentials.request_fact(asset_id)
        rescue
          raise ValidationError, <<~ERROR.chomp
            Could not access the metadata for the specified asset
            Try regenerating the API token and try again

            Please contact your system administrator if this error persists
          ERROR
        end
      else
        raise InputError, 'Validation is not possible in multi-asset mode'
      end
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
end
