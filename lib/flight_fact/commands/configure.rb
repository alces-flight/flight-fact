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

require 'tty-prompt'
require_relative '../config_updater'

module FlightFact
  module Commands
    class Configure < Command
      def run
        if $stdout.tty? && opts.select { |_, v| v }.empty?
          # Run interactively if connected to a TTY without options
          run_interactive
        else
          # Run non interactively
          run_non_interactive
        end
      end

      def run_interactive
        # Prompt for the JWT
        old_jwt_mask = mask(updater.jwt)
        opts = { required: true }.tap { |o| o[:default] = old_jwt_mask if updater.jwt }
        new_jwt = prompt.ask 'Flight Center API token:', **opts
        updater.jwt = new_jwt unless new_jwt == old_jwt_mask

        validatable = prompt.select('How should the asset(s) be configured?') do |menu|
          menu.instance_variable_set(:@cycle, true)
          default = if Config::CACHE.implicit_static_asset?
            2 # By name
          elsif Config::CACHE.static_asset?
            1 # By ID
          else
            3 # Multiple
          end
          menu.default default

          # NOTE: These are order dependent so the default works
          menu.choice 'Single asset by ID' do
            opts = { required: true }.tap do |o|
              o[:default] = Config::CACHE.static_asset_id if Config::CACHE.explicit_static_asset?
            end
            updater.asset_id = prompt.ask 'What is the asset ID?', **opts
            true
          end
          menu.choice 'Single asset by name' do
            updater.asset_name = prompt.ask('What is the asset name?', default: Config::CACHE.unresolved_asset_name)
            true
          end
          menu.choice 'Multiple assets' do
            updater.asset_id = nil
            false
          end
        end

        # Prompts if the user wants to run the validator, disabled in multi mode
        updater.validate if validatable && prompt.yes?('Do you wish to run the validation?', default: false)

        updater.save
      end

      def run_non_interactive
        if opts.jwt && opts.jwt.empty?
          updater.jwt = nil
        elsif opts.jwt
          updater.jwt = opts.jwt
        end

        if opts.asset && opts.asset.empty?
          updater.asset_id = nil
        elsif opts.asset && opts.id
          updater.asset_id = opts.asset
        elsif opts.asset
          updater.asset_name = opts.asset
        end

        updater.validate if opts.validate

        updater.save
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def updater
        @updater ||= ConfigUpdater.new.tap(&:assert_writable)
      end

      def mask(jwt)
        return nil if jwt.nil?
        return ('*' * jwt.length) if jwt[-8..-1].nil?
        ('*' * 24) + jwt[-8..-1]
      end
    end
  end
end

