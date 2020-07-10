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

require 'paint'
require 'csv'
require 'stringio'

module FlightFact
  module Commands
    class List < Command
      def run
        data = request_fact
        if data.empty?
          $stderr.puts 'No fact entries found!'
        else
          puts render(data)
        end
      end

      def render(data)
        if $stdout.tty?
          # Determines the max width
          max = data.max { |h, v| h.length }[0].length

          # Pads the results
          padded = data.map do |header, value|
            ["#{' ' * (max - header.length)}#{header}", value]
          end

          # Colorizes the results
          padded.map do |key, raw|
            header = Paint[key + ':', '#2794d8']
            value = Paint[raw, :green]
            "#{header} #{value}"
          end.join("\n")
        else
          io = StringIO.new
          csv = CSV.new(io, col_sep: "\t")
          csv << data.keys
          csv << data.values
          io.rewind
          io.read
        end
      end
    end
  end
end

