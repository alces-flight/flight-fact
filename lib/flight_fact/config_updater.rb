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
    attr_reader :jwt, :asset_name, :asset_id, :old_credentials

    ##
    # Sets the asset_name/asset_id based on the initial values
    def initialize
      if Config::CACHE.implicit_static_asset?
        self.asset_name = Config::CACHE.unresolved_asset_name
      elsif Config::CACHE.static_asset?
        self.asset_id = Config::CACHE.static_asset_id
      end
      @old_credentials = Config::CACHE.load_credentials
      @jwt = old_credentials.jwt
      @main_changed = false
      @credentials_changed = false
    end

    ##
    # Sets the jwt and flags if the credentials have changed
    def jwt=(token)
      if old_credentials.jwt.to_s != token.to_s
        @jwt = token
        @credentials_changed = true
      end
    end

    ##
    # Sets the asset_id and flags if the main config has changed
    def asset_id=(id)
      if Config::CACHE.static_asset_id.to_s != id.to_s
        @asset_name = nil
        @asset_id = id
        @main_changed = true
      end
    end

    ##
    #
    def asset_name=(name)
      if Config::CACHE.unresolved_name.to_s != name.to_s
        @asset_name = name
        @asset_id = nil
        @main_changed = true
      end
    end

    def main_changed?
      @main_changed ? true : false
    end

    def credentials_changed?
      @credentials_changed ? true : false
    end

    # TODO: Reinstate ID resolution
    # Config::CACHE.fetch_asset_id_by_name(name)
    # rescue
    #   # Logs the asset name wasn't resolve but flags the asset_id as truthy
    #   # This will trigger the name to be resolved at some future point - hopefully
    #   @asset_id = true
    #   Config::CACHE.logger.error <<~ERROR.chomp.chomp
    #     Failed to resolve asset: #{name}. Continuing with an unresolved asset name.
    #   ERROR
    # end

    ##
    # Saves both the credentials file and updated config
    def save
      # Ensures the user has permission to write to the updated configs
      assert_writable(CONFIG_PATH) if main_changed?
      assert_writable(new_main.credentials_path) if credentials_changed?

      # Updates the main config
      new_main = Config::CACHE
      if main_changed?
        new_main_hash = build_main_hash
        new_main = Config.new(new_main_hash)
        Config::CACHE.logger.info "Updating: #{CONFIG_PATH}"
        File.write(CONFIG_PATH, YAML.dump(new_main_hash))
      else
        Config::CACHE.logger.warn "Skipping: #{CONFIG_PATH}"
      end

      # Updates the credentials
      if credentials_changed?
        Config::CACHE.logger.info "Updating: #{new_main.credentials_path}"
        File.write new_main.credentials_path, YAML.dump(build_credentials_hash)
      else
        Config::CACHE.logger.warn "Skipping: #{new_main.credentials_path}"
      end
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
          CredentialsConfig.new(jwt: jwt).request_fact(asset_id)
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
    # Returns the hash representation of the main config without the defaults
    def build_main_hash
      Config::CACHE.to_h.dup.tap do |h|
        h['static_asset_id'] = asset_id
        if asset_name.nil?
          h.delete('unresolved_asset_name')
        else
          h['unresolved_asset_name'] = asset_name
        end

        # Remove the default values
        blank = Config.new.to_h
        h.reject! { |k, v| blank[k] == v }
      end
    end

    ##
    # Returns the hash representation of the credentials config
    def build_credentials_hash
      old_credentials.to_h.dup do |h|
        if jwt.nil? || jwt.empty?
          h.delete('jwt')
        else
          h['jwt'] = jwt
        end
      end
    end

    ##
    # Used to ensure a user can write to a particular path, either by:
    # * Writing the existing content back to the file, or
    # * Touching a blank file if missing (then removing it)
    def assert_writable(path)
      if File.exists? path
        File.write path, File.read(path)
      else
        FileUtils.mkdir_p File.dirname(path)
        FileUtils.touch path
        FileUtils.rm path
      end
    rescue
      raise PermissionError, <<~ERROR.chomp
        You do not have permission to update the following config: #{path}
      ERROR
    end
  end
end
