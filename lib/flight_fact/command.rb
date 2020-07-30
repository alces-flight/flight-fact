#==============================================================================
# Copyright (C) 2019-present Alces Flight Ltd.
#
# This file is part of Flight Fact.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Fact is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Fact. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Fact, please visit:
# https://github.com/alces-flight/alces-flight/flight-fact
#==============================================================================

require 'active_support/concern'
require 'active_support/core_ext/module/delegation'
require 'json'
require 'open3'

require 'forwardable'

require_relative 'errors'
require_relative 'config'

module FlightFact
  class Command
    extend Forwardable

    def self.define_args(*names)
      names.each_with_index do |name, index|
        define_method(name) { args[index] }
      end
    end

    attr_reader :args, :opts

    def initialize(*args, **opts)
      @args = args.dup
      @opts = Hashie::Mash.new(**opts.dup)
    end

    ##
    # Runs the man 'run' method with the callbacks
    #
    def run!
      Config::CACHE.logger.info "Running: #{self.class}"
      begin
        run
      end
      Config::CACHE.logger.info 'Exited: 0'
    rescue => e
      if e.respond_to? :exit_code
        Config::CACHE.logger.fatal "Exited: #{e.exit_code}"
      else
        Config::CACHE.logger.fatal 'Exited non-zero'
      end
      Config::CACHE.logger.debug e.backtrace.reverse.join("\n")
      Config::CACHE.logger.error "(#{e.class}) #{e.message}"
      raise e
    end

    ##
    # The main runner method that preforms the action
    def run
    end

    ##
    # @return [Flight::Fact::CredentialsConfig] the cached credentials object
    def credentials
      @credentials ||= Config::CACHE.load_credentials
    end
    def_delegators :credentials, :connection, :fetch_asset_id_by_name

    ##
    # @return [String] the asset id associated with the command
    def asset_id
      @asset_id ||= if opts.asset
        fetch_asset_id_by_name(opts.asset)
      elsif id = credentials.resolve_asset_id
        id
      else
        raise InputError, <<~ERROR.chomp
          This installation has not been configured with a default asset.
          Please do one of the following:
           * Re-run the command with: --asset NAME
           * Or configure the default asset: #{Config::CACHE.app_name} configure
        ERROR
      end
    end

    def save_credentials
      path = Config::CACHE.credentials_path
      Config::CACHE.logger.info "Saving credentials: #{path}"
      FileUtils.mkdir_p File.dirname(path)
      File.write path, YAML.dump(credentials.to_h)
    end

    def key_url(key)
      # Prevent the key exceeding the maximum length
      raise InputError, <<~ERROR.chomp if key.length > Config::CACHE.max_key_length
        The following key exceeds the maximum length: #{key[0..10]}...
        The maximum length is #{Config::CACHE.max_key_length} characters
      ERROR

      File.join('assets', asset_id, 'metadata', key)
    end

    ##
    # Finds the fact associated with the (see #connection)
    # @return [Hash] the fact associated with the asset
    # @raises InternalError the asset is missing or the connection has been missed configured
    def request_fact
      connection.get(File.join('assets', asset_id, 'metadata')).body
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    ##
    # Returns an entry via it's key
    def request_get_entry(key)
      connection.get(key_url key).body
    rescue Faraday::ResourceNotFound
      raise MissingError, <<~ERROR.chomp
        Could not find an entry for: #{key}
      ERROR
    end

    ##
    # Sets a key-value pair against the asset
    def request_set_entry(key, value)
      connection.put(key_url(key), JSON.dump(value))
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    ##
    # Permanently unset an entry
    def request_delete_entry(key)
      connection.delete(key_url key)
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    def raise_missing_asset
      raise InternalError, <<~ERROR.chomp
        Could not find the specified asset by its identifier
        Please contact your system administrator for futher assistance
      ERROR
    end
  end
end

