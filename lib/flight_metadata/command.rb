#==============================================================================
# Copyright (C) 2019-present Alces Flight Ltd.
#
# This file is part of Flight Metadata.
#
# This program and the accompanying materials are made available under
# the terms of the Eclipse Public License 2.0 which is available at
# <https://www.eclipse.org/legal/epl-2.0>, or alternative license
# terms made available by Alces Flight Ltd - please direct inquiries
# about licensing to licensing@alces-flight.com.
#
# Flight Metadata is distributed in the hope that it will be useful, but
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, EITHER EXPRESS OR
# IMPLIED INCLUDING, WITHOUT LIMITATION, ANY WARRANTIES OR CONDITIONS
# OF TITLE, NON-INFRINGEMENT, MERCHANTABILITY OR FITNESS FOR A
# PARTICULAR PURPOSE. See the Eclipse Public License 2.0 for more
# details.
#
# You should have received a copy of the Eclipse Public License 2.0
# along with Flight Metadata. If not, see:
#
#  https://opensource.org/licenses/EPL-2.0
#
# For more information on Flight Metadata, please visit:
# https://github.com/alces-flight/alces-flight/flight-metadata
#==============================================================================

require 'active_support/callbacks'
require 'active_support/concern'
require 'active_support/core_ext/module/delegation'

require_relative 'errors'
require_relative 'config'

module FlightMetadata
  class Command
    include ActiveSupport::Callbacks

    define_callbacks :run

    CALLBACK_FILTER_TYPES.each do |type|
      define_singleton_method(type) do |**opts, &block|
        do_block = opts.delete(:do)
        set_callback(:run, type, **opts, &(do_block || block))
      end
    end

    attr_reader :args, :opts

    def self.define_args(*names)
      names.each_with_index do |name, index|
        define_method(name) { args[index] }
      end
    end

    def initialize(*args, **opts)
      @args = args.dup
      @opts = Hashie::Mash.new(**opts.dup)
    end

    ##
    # Runs the man 'run' method with the callbacks
    #
    def run!
      Config::CACHE.logger.info "Running: #{self.class}"
      run_callbacks(:run) { run }
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
    # @return [Flight::Metadata::CredentialsConfig] the cached credentials object
    def credentials
      @credentials ||= Config::CACHE.load_credentials
    end

    ##
    # @return [String] fetches the asset id associated with the command
    def request_asset_id
      # TODO: Fetch id associated with --asset
      credentials.asset_id
    end

    ##
    # @return [Faraday::Connection] the cached connection to the api
    def connection
      @connection ||= credentials.build_connection
    end

    ##
    # Finds the metadata associated with the (see #connection)
    # @return [Hash] the metadata associated with the asset
    # @raises InternalError the asset is missing or the connection has been missed configured
    def request_metadata
      connection.get(File.join('assets', request_asset_id, 'metadata')).body
    rescue Faraday::ResourceNotFound
      raise InternalError, <<~ERROR.chomp
        Could not find the specified asset by its identifier
        Please contact your system administrator for futher assistance
      ERROR
    end
  end
end

