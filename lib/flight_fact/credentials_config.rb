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
require 'jwt'

module FlightFact
  class JWTCheckMiddleware
    attr_reader :jwt

    def initialize(app, jwt:)
      @app = app
      @jwt = jwt
    end

    def call(env)
      env.request_headers['Authorization'] = "Bearer #{jwt}"
      @app.call(env).tap do |res|
        # Checks if the 404 was "likely" caused by an invalid JWT
        check_token if res.status == 404
      end
    end

    def check_token
      expiry = begin
        JWT.decode(jwt, nil, false).first['exp']
      rescue
        raise CredentialsError, <<~ERROR.chomp
          Your access token appears to be malformed and needs to be regenerated.
          Please take care when copying the token into the configure command:
          #{Paint["#{Config::CACHE.app_name} configure --jwt TOKEN", :yellow]}
        ERROR
      end

      if expiry && expiry < Time.now.to_i
        raise CredentialsError, <<~ERROR.chomp
          Your access token has expired! Please regenerate it and run:
          #{Paint["#{Config::CACHE.app_name} configure --jwt JWT", :yellow]}
        ERROR
      end
    end
  end

  class CredentialsConfig < Hashie::Dash
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::Dash::IndifferentAccess

    property :jwt

    def jwt?
      !(jwt.nil? || jwt.empty?)
    end

    def jwt=(value)
      if value&.empty?
        self.delete(:jwt)
      else
        self[:jwt] = value
      end
    end

    def headers
      {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
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
          c.use JWTCheckMiddleware, jwt: jwt
          c.use Faraday::Response::Logger, Config::CACHE.logger, { bodies: true } do |l|
            l.filter(/(Authorization:)(.*)/, '\1 [REDACTED]')
          end
          c.request :json
          c.adapter :net_http
        end
      end
    end

    def request_fact(asset_id)
      connection.get(File.join('assets', asset_id, 'metadata')).body
    end
  end
end

