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

require 'json'
require 'open3'
require 'paint'
require 'uri'

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

    attr_reader :args, :opts, :credentials, :args_asset
    def_delegators :credentials, :connection

    def initialize(*args, credentials: nil, args_asset: nil, **opts)
      @args = args.dup
      @opts = Hashie::Mash.new(**opts.dup)
      @credentials = credentials || Config::CACHE.load_credentials
      @args_asset = args_asset
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
    # @return [String] the asset id associated with the command
    def asset_id
      @asset_id ||= if args_asset
        Config::CACHE.fetch_asset_id_by_name(args_asset)
      elsif Config::CACHE.asset_id?
        Config::CACHE.asset_id
      else
        raise InternalError, <<~ERROR.chomp
          An unexpected error has occurred!
          The application does not appear to be correctly configured
          Please contact your system administrator for further assistance
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

      # Splits on white space characters without removing them
      # NOTE: All values but the last end with a single white space character
      #       This is to allow the correct encoding to be used per space character
      key_parts = key.split(/(?<=\s)/)
      last_part = key_parts.pop

      # Forms a 2D array of key parts and their corresponding white space character
      # NOTE: The last part does not have a corresponding white space character
      parts_2d = key_parts.map { |k| [k[0..-2], k[-1]] }
      parts_2d << [last_part, '']

      # Encodes the non-white space and white space character different, because ruby ¯\_(ツ)_/¯
      encoded = parts_2d.map do |non_white, white|
        [URI.encode_www_form_component(non_white).gsub('.', '%2E'), URI.encode(white)]
      end.flatten.join

      # Uses the now encoded character
      File.join('assets', asset_id, 'metadata', encoded)
    end

    ##
    # Finds the fact associated with the asset (see #connection)
    # @return [Hash] the fact associated with the asset
    # @raises InternalError the asset is missing or the connection has been missed configured
    def request_fact
      credentials.request_fact(asset_id)
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    ##
    # Returns an entry via it's key
    def request_get_entry(key)
      connection.get(key_url key).body
    rescue Faraday::ResourceNotFound
      raise MissingKey, <<~ERROR.chomp
        Could not find an entry for: #{key}
      ERROR
    end

    ##
    # Sets a key-value pair against the asset
    def request_set_entry(key, value)
      raise InputError, <<~ERROR.chomp if value.length > Config::CACHE.max_value_length
        The following value exceeds the maximum length: #{value[0..10]}...
        The maximum length is #{Config::CACHE.max_value_length} characters
      ERROR

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

