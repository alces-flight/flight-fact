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

require_relative 'errors'
require_relative 'config'

module FlightFact
  class Command
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

    ##
    # @return [String] the asset id associated with the command
    def asset_id
      if opts.asset
        fetch_asset_id_by_name(opts.asset)
      else
        credentials.asset_id
      end
    end

    ##
    # @return [Faraday::Connection] the cached connection to the api
    def connection
      @connection ||= credentials.build_connection
    end

    def relative_url(*a)
      File.join('assets', asset_id, 'metadata', *a)
    end

    ##
    # Finds the fact associated with the (see #connection)
    # @return [Hash] the fact associated with the asset
    # @raises InternalError the asset is missing or the connection has been missed configured
    def request_fact
      connection.get(relative_url).body
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    def fetch_asset_id_by_name(name)
      cmd = "#{Config::CACHE.asset_command} show #{name}"
      Config::CACHE.logger.info "Running: #{cmd}"
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(*cmd.split(' '))
      end
      if status.exitstatus == 0
        Config::CACHE.logger.info "Flight Asset: #{status}"
        stdout.chomp.split("\t")[5]
      elsif status.exitstatus == 21
        Config::CACHE.logger.error "Flight Asset: #{status}"
        raise MissingError, <<~ERROR.chomp
          Could not locate asset: #{name}
        ERROR
      else
        Config::CACHE.logger.error "Flight Asset: #{status}"
        Config::CACHE.logger.debug stdout
        Config::CACHE.logger.error stderr
        raise InternalError, <<~ERROR.chomp
          An unexpected error has occurred!
          Please ensure the following executes correctly and try again:
          #{cmd}
        ERROR
      end
    end

    ##
    # Returns an entry via it's key
    def request_get_entry(key)
      connection.get(relative_url(key)).body
    rescue Faraday::ResourceNotFound
      raise MissingError, <<~ERROR.chomp
        Could not find an entry for: #{key}
      ERROR
    end

    ##
    # Sets a key-value pair against the asset
    def request_set_entry(key, value)
      connection.put(relative_url(key), JSON.dump(value))
    rescue Faraday::ResourceNotFound
      raise_missing_asset
    end

    ##
    # Permanently unset an entry
    def request_delete_entry(key)
      connection.delete(relative_url(key))
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

