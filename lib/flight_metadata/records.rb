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

module FlightMetadata
  class BaseRecord < SimpleJSONAPIClient::Base
    # Defines a method to index a particular URL, very few protections are in
    # place. However it should page responses correctly
    def self.index_enum(**base_opts)
      Enumerator.new do |yielder|
        nxt = ''
        known = {}

        # Pages the subsequent requests
        while nxt do
          # Extracts the opts from the next request
          #
          # HACK: BUG IN PAGING RESULTS
          # The API links sometimes returns nxt links like the following.
          # Note how there are two sets of query parameters:
          # https://example.com/api/v1/components/3/assets?page%5Bnumber%5D=3&page%5Bsize%5D=10?page%5Bnumber%5D=2&page%5Bsize%5D=10
          #
          # The first set of query parameters are from the request and can
          # be considered junk. The last set are the actual `page[number]`
          # and `page[size]` for the next request. The next URL must be
          # reformed otherwise all sorts of erroneous requests could be made
          nxt_params = CGI.parse(nxt.split('?').last || '')
          new_opts = ['size', 'number'].map do |key|
            [key, nxt_params.fetch("page[#{key}]", []).first]
          end.reject { |_, v| v.nil? }.to_h
          page_opts = ( base_opts[:page_opts] || {} ).merge(new_opts)
          opts = base_opts.merge(page_opts: page_opts)

          # Makes the next request
          res = operation(:fetch_all_request, :plural, **opts)

          # Extracts the required links
          slf, nxt = ['self', 'next'].map do |key|
            (res['links'] || {}).fetch(key, nil)
          end

          # Registers the response as known and errors on duplicates
          raise InternalError, <<~ERROR.chomp if known[slf]
            Caught in request loop for: #{slf}
          ERROR
          known[slf] = true

          # Register the records on the enumerator
          res['data'].each { |d| yielder << d }
        end
      end
    end

    def self.fetch_all_request(connection:,
                               url_opts: {},
                               url: self::COLLECTION_URL % url_opts,
                               filter_opts: {},
                               field_opts: [],
                               page_opts: {},
                               includes: [])
      params = {}
      params[:include] = includes.join(',') unless includes.empty?
      params[:filter] = filter_opts unless filter_opts.empty?
      params[:page] = page_opts unless page_opts.empty?
      params[:fields] = field_opts unless field_opts.empty?
      connection.get(url, params)
    end
  end
end

