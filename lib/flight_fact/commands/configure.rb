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
      def run
        raise InteractiveOnly unless $stdout.tty?
        configure_jwt
        configure_default_asset
        File.write Config::CACHE.credentials_path, YAML.dump(data.to_h)
      end

      def configure_jwt
        old_jwt_mask = mask(data.jwt)
        opts = { required: true }.tap { |o| o[:default] = old_jwt_mask if data.jwt }
        new_jwt = prompt.ask 'Flight Center API token:', **opts
        data.jwt = new_jwt unless new_jwt == old_jwt_mask
      end

      def configure_default_asset
        if prompt.yes? "Define the default asset by ID?", default: (data.asset_id ? true : false)
          opts = { requried: true }.tap do |o|
            o[:default] = data.asset_id if data.asset_id
          end
          data.asset_id = prompt.ask 'Default Asset ID:', **opts
        elsif prompt.yes? "Define the default asset by name?", default: true
          name = prompt.ask "Default Asset Name:", default: `hostname`.chomp
          data.asset_id = fetch_asset_id_by_name(name)
        elsif data.asset_id
          $stderr.puts 'Removing previously set default asset'
          data.asset_id = nil
        end
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def data
        @data ||= Config::CACHE.load_credentials
      end

      def mask(jwt)
        return nil if jwt.nil?
        return ('*' * jwt.length) if jwt[-8..-1].nil?
        ('*' * 24) + jwt[-8..-1]
      end
    end
  end
end

