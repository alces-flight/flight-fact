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
    attr_accessor :jwt
    attr_reader :asset_name, :asset_id, :old_credentials

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
      # Gets the original versions of the configs
      original_main_hash = Config::CACHE.to_h
      original_credentials_hash = old_credentials.to_h

      # Builds the updated content
      main_hash = build_main_hash
      credentials_hash = build_credentials_hash

      # Builds the new config
      new_main = Config.new(**main_hash)

      # Determines which configs need updating
      changed = []
      changed << :main unless original_main_hash == main_hash
      changed << :credentials unless original_credentials_hash == credentials_hash

      # Ensures the user has permission to write to the updated configs
      assert_writable(CONFIG_PATH) if changed.include?(:main)
      assert_writable(new_main.credentials_path) if changed.include?(:credentials)

      # Updates the main config (without saving the defaults)
      if changed.include?(:main)
        Config::CACHE.logger.info "Updating: #{CONFIG_PATH}"
        blank = Config.new.to_h
        data = main_hash.reject { |k, v| blank[k] == v }.to_h
        File.write(CONFIG_PATH, YAML.dump(data))
      else
        Config::CACHE.logger.warn "Skipping: #{CONFIG_PATH}"
      end

      # Updates the credentials
      if changed.include?(:credentials)
        Config::CACHE.logger.info "Updating: #{new_main.credentials_path}"
        File.write new_main.credentials_path, YAML.dump(credentials_hash)
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
    # Returns the hash representation of the main config
    def build_main_hash
      Config::CACHE.to_h.dup.tap do |h|
        h[:static_asset_id] = asset_id
        if asset_name.nil?
          h.delete(:unresolved_asset_name)
        else
          h[:unresolved_asset_name] = asset_name
        end
      end
    end

    ##
    # Returns the hash representation of the credentials config
    def build_credentials_hash
      old_credentials.to_h.dup do |h|
        if jwt.nil? || jwt.empty?
          h.delete(:jwt)
        else
          h[:jwt] = jwt
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
