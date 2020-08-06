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
        raise NotImplementedError
      end

      def run_non_interactive
        raise NotImplementedError
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def mask(jwt)
        return nil if jwt.nil?
        return ('*' * jwt.length) if jwt[-8..-1].nil?
        ('*' * 24) + jwt[-8..-1]
      end
    end
  end
end

