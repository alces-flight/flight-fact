# frozen_string_literal: true
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

require 'faraday'
require 'faraday_middleware'

module FlightFact
  class CredentialsConfig < Hashie::Dash
    property :jwt
    property :asset_id
    property :unresolved_name

    def jwt?
      !(jwt.nil? || jwt.empty?)
    end

    def headers
      {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{jwt}"
      }
    end

    ##
    # Create a new connection to the api
    def connection
      @connection ||= begin
        url = File.join(Config::CACHE.base_url!, Config::CACHE.api_prefix!)
        Faraday.new(url: url, headers: headers) do |c|
          c.response :json, :content_type => /\bjson$/
          c.use Faraday::Response::RaiseError
          c.use Faraday::Response::Logger, Config::CACHE.logger, { bodies: true } do |l|
            l.filter(/(Authorization:)(.*)/, '\1 [REDACTED]')
          end
          c.request :json
          c.adapter :net_http
        end
      end
    end

    ##
    # @returns [Boolean] true iff the name requires and is resolved
    def resolve?
      asset_id != resolve_asset_id
    end

    ##
    # Interprets the asset_id and asset_name in tandem. The underlining
    # assumption is the asset_id is always correct. It is the responsibility
    # of the Configure command to unset it
    def resolve_asset_id
      if asset_id
        asset_id
      elsif unresolved_name
        self.asset_id = fetch_asset_id_by_name(unresolved_name)
      end
    end

    ##
    # NOTE: ANTI-PATTERN ALERT!
    # Both the CredentialsConfig and Command objects require the ability to
    # resolve asset names to ids. As each Command object already stores a
    # CredentialsConfig, the best place to store it is here.
    #
    # The method DOES NOT USE this object as it's credentials. It integrates
    # with 'flight-asset' which must be configured independently.
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
          #{Paint[cmd, :yellow]}
        ERROR
      end
    end
  end
end

