require 'sequel'
require 'multi_json'
require 'ostruct'
require 'bogo'

require 'fission-data/version'
require 'fission'

module Fission
  module Data

    # Data configuration path
    FISSION_DATA_CONFIG = '/etc/fission/sql.json'

    class << self

      # @return [Logger] return best fit logger
      def logger
        if(defined?(Rails))
          Rails.logger
        elsif(defined?(Carnivore))
          Carnivore::Logger
        else
          require 'logger'
          Thread.current[:fission_data_logger] ||= Logger.new($stdout)
        end
      end

      # Establish connection
      #
      # @param args [Hash]
      def connect!(args=Hash.new)
        unless($dbcon)
          if(args.empty? || args[:file])
            args = connection_arguments(args[:file])
          end
          Sequel.extension :core_extensions
          Sequel.extension :pg_array
          Sequel.extension :pg_json
          Sequel.extension :pg_json_ops
          Sequel.extension :migration
          if(RUBY_PLATFORM == 'java')
            args = "jdbc:#{args[:adapter]}://#{args[:host]}/#{args[:database]}?user=#{args[:user]}&password=#{args[:password]}"
          end
          $dbcon = db = Sequel.connect(args)
          db.extension :pagination
          migrate!(db)
        end
      end

      # Migrate database
      #
      # @param db [Sequel::Database]
      def migrate!(db)
        Sequel::Migrator.run(db, File.join(File.dirname(__FILE__), 'fission-data', 'migrations'))
      end

      # Load connection arguments
      #
      # @param path [String] path to configuration JSON
      # @return [Hash]
      def connection_arguments(path=nil)
        path = [path, ENV['FISSION_DATA_CONFIG'] || FISSION_DATA_CONFIG].detect do |test_path|
          File.exists?(test_path.to_s)
        end
        default_args = {
          :adapter => RUBY_PLATFORM == 'java' ? 'postgresql' : 'postgres',
          :database => 'fission',
          :host => 'localhost',
          :user => 'fission',
          :password => 'fission-password'
        }
        if(path)
          default_args.merge(
            MultiJson.load(File.read(path), :symbolize_keys => true)
          )
        else
          default_args
        end
      end

    end
  end
end


module Fission
  # Data models for Fission
  module Data

    autoload :Error, 'fission-data/errors'
    autoload :Model, 'fission-data/models'
    autoload :Models, 'fission-data/models'
    autoload :Utils, 'fission-data/utils'

  end
end
