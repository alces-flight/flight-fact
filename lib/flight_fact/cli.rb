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

    def self.create_command(name, args_str = '')
      command(name) do |c|
        c.syntax = "#{program :name} #{name} #{args_str}"
        c.hidden = true if name.split.length > 1

        c.action do |args, opts|
          require_relative 'commands'
          Commands.build(name, *args, **opts.to_h).run!
        end

        yield c if block_given?
      end
    end

    program :name, Config::CACHE.app_name!
    program :version, "v#{FlightFact::VERSION}"
    program :description, 'Manage Alces Flight Center Assets'
    program :help_paging, false

    # create_command 'configure' do |c|
    #   c.summary = 'Configure the application'
    # end

    global_slop.bool '--verbose', <<~DESC.chomp
      Display the full details when used in an interactive terminal.
      Non-interactive terminals follow the same output layouts and are always verbose.
    DESC

    create_command('configure') do |c|
      c.summary = 'Initial application setup'
    end

    create_command('list') do |c|
      c.summary = 'View all fact entries'
    end

    create_command('get', 'KEY') do |c|
      c.summary = 'View a fact entry'
    end

    create_command('set', 'KEY VALUE') do |c|
      c.summary = 'Set a fact entry'
    end

    create_command('delete', 'KEY') do |c|
      c.summary = 'Permanentely remove a fact entry'
    end

    if Config::CACHE.development?
      create_command 'console' do |c|
        c.action do |args, opts|
          require_relative 'commands'
          Command.new(*args, **opts.to_h).pry
        end
      end
    end
  end
end
