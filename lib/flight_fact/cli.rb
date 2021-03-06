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

require 'commander'
require_relative 'version'

module FlightFact
  class CLI
    extend Commander::CLI

    ##
    # Used by the CLI to define the method signatures, it may become stale
    # depending which commands have been ran (e.g. configure)
    def self.cached_credentials
      @cached_credentials ||= Config::CACHE.load_credentials
    end

    def self.create_command(name, args_str = '', auto_asset: true)
      command(name) do |c|
        if auto_asset && !Config::CACHE.asset_id?
          c.syntax = "#{program :name} #{name} ASSET #{args_str}"
        else
          c.syntax = "#{program :name} #{name} #{args_str}"
        end
        c.hidden = true if name.split.length > 1

        c.action do |args, opts|
          require_relative 'commands'

          # Injects the cached credentials onto the command and resets the cache
          old = cached_credentials
          @cached_credentials = nil

          # Determines if an asset has been provided with the command
          asset = c.syntax.include?('ASSET') ? args.shift : nil

          Commands.build(name, *args, credentials: old, args_asset: asset, **opts.to_h)
                  .run!
        end

        yield c if block_given?
      end
    end

    program :application, 'Flight Fact'
    program :name, Config::CACHE.app_name
    program :version, "v#{FlightFact::VERSION}"
    program :description, 'Manage Alces Flight Center asset metadata entries'
    program :help_paging, false

    create_command('configure', auto_asset: false) do |c|
      c.summary = 'Initial application setup'
      c.slop.string '--jwt', "Update the API access token. Unset with empty string: ''"
    end

    create_command('list') do |c|
      c.summary = 'View all fact entries'
      c.slop.bool '--keys-only', 'Return the known keys without the associated values'
    end

    create_command('get', 'KEY') do |c|
      c.summary = 'View a fact entry'
    end

    create_command('set', 'KEY VALUE') do |c|
      c.summary = 'Set a fact entry'
      special_keys_description = ''
      unless (hash = Config::CACHE.allowed_special_keys).keys.empty?
        max = hash.keys.map(&:length).max
        special_keys_description += <<~DESC.chomp


          Certain keys have special status within Alces Flight Center UI and may
          only have the following values:
          #{hash.map { |k, v| " * #{' ' * (max - k.length)}#{k}: #{v.join(', ')}" }.join("\n")}
        DESC
      end
      unless (keys = Config::CACHE.disabled_special_keys).empty?

        special_keys_description += <<~DESC.chomp


          The following key#{'s' if keys.length > 1} must not be set:
          #{keys.map { |k| " * #{k}" }.join("\n")}
        DESC
      end

      c.description = <<~DESC.chomp
        Set the VALUE for the metadata entry KEY.#{special_keys_description}
      DESC
    end

    create_command('delete', 'KEY') do |c|
      c.summary = 'Permanentely remove a fact entry'
    end

    if Config::CACHE.development?
      create_command 'console', auto_asset: false do |c|
        c.action do |args, opts|
          require_relative 'commands'
          Command.new(*args, **opts.to_h).pry
        end
      end
    end
  end
end
