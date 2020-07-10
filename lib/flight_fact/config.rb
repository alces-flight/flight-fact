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

require 'yaml'
require 'logger'
require 'hashie'
require 'xdg'

require_relative 'credentials_config.rb'

module FlightFact
  REFERENCE_PATH = File.expand_path('../../etc/config.reference', __dir__)
  CONFIG_PATH = File.expand_path('../../etc/config.yaml', __dir__)

  class Config < Hashie::Trash
    include Hashie::Extensions::IgnoreUndeclared
    include Hashie::Extensions::Dash::IndifferentAccess

    def self.config(sym, **input_opts)
      opts = input_opts.dup

      # Make keys with defaults required by default
      opts[:required] = true if opts.key? :default && !opts.key?(:required)

      bang_nil_result = if transform = opts[:transform_with]
        # Set the bang method nil result from the transform
        transform.call(nil)
      else
        # By default convert empty string to nil
        opts[:transform_with] = ->(v) { v == '' ? nil : v }

        # Return nil as empty string through the bang method
        ''
      end

      # Defines the underlining property
      property(sym, **opts)

      # Return the bang result through the bang method if nil
      define_method(:"#{sym}!") do
        value = send(sym)
        value.nil? ? bang_nil_result : value
      end

      # Define the truthiness method
      define_method(:"#{sym}?") { send(sym) ? true : false }
    end

    def self.xdg
      @xdg ||= XDG::Environment.new
    end

    def self.load_reference(path)
      self.instance_eval(File.read(path), path, 0) if File.exists?(path)
    end

    config :development

    def credentials_path
      File.join(config_path, 'credentials.yaml')
    end

    def load_credentials
      if File.exists? credentials_path
        data = YAML.load File.read(credentials_path), symbolize_names: true
        CredentialsConfig.new data
      else
        logger.error <<~ERROR
          Could not locate: #{credentials_path}
          Using a blank config instead
        ERROR
        CredentialsConfig.new
      end
    end

    def log_path_or_stderr
      if log_level == 'disabled'
        '/dev/null'
      elsif log_path
        FileUtils.mkdir_p File.dirname(log_path)
        log_path
      else
        $stderr
      end
    end

    def logger
      @logger ||= Logger.new(log_path_or_stderr).tap do |log|
        next if log_level == 'disabled'

        # Determine the level
        level = case log_level
        when 'fatal'
          Logger::FATAL
        when 'error'
          Logger::ERROR
        when 'warn'
          Logger::WARN
        when 'info'
          Logger::INFO
        when 'debug'
          Logger::DEBUG
        end

        if level.nil?
          # Log bad log levels
          log.level = Logger::ERROR
          log.error "Unrecognized log level: #{log_level}"
        else
          # Sets good log levels
          log.level = level
        end
      end
    end
  end

  # Loads the reference file
  Config.load_reference REFERENCE_PATH

  # Caches the config
  Config::CACHE = if File.exists? CONFIG_PATH
    data = File.read(CONFIG_PATH)
    Config.new(YAML.load(data, symbolize_names: true)).tap do |c|
      c.logger.info "Loaded Config: #{CONFIG_PATH}"
      c.logger.debug data.gsub(/(?<=jwt)\s*:[^\n]*/, ': REDACTED')
    end
  else
    Config.new({}).tap do |c|
      c.logger.info "Missing Config: #{CONFIG_PATH}"
    end
  end
end

