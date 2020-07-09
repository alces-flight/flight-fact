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

require_relative 'command'

module FlightMetadata
  module Commands
    Dir.glob(File.expand_path('commands/*.rb', __dir__)).each do |file|
      autoload File.basename(file, '.*').captilalize.to_sym, file
    end

    class << self
      def build(s, *args, **opts)
        name = s.to_s.dup.split('-').map { |c| c[0] = c[0].upcase; c }.join
        klass = self.const_get(name)
        klass.new(*args, **opts)
      rescue NameError
        raise InternalError, 'Command Not Found!'
      end
    end
  end
end

