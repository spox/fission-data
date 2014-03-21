require 'risky'
require 'fission-data'

module Fission
  module Data

    module Riak

      FISSION_RIAK_CONFIG = '/etc/fission/riak.json'

      class << self
        def connect!(args=Hash.new)
          if(args.empty? || args[:file])
            args = connection_arguments(args[:file])
          end
          Risky.riak = ::Riak::Client.new(args)
        end

        def connection_arguments(path=nil)
          path = [path, ENV['FISSION_RIAK_CONFIG'] || FISSION_RIAK_CONFIG].detect do |test_path|
            File.exists?(test_path.to_s)
          end
          raise 'Failed to discover valid path for riak connection configuration!' unless path
          Fission::Data::Hash.symbolize_hash(
            MultiJson.load(File.read(path))
          )
        end
      end

    end

    class << self
      def connect!
        Riak.connect!
      end
    end

    Dir.glob(File.join(File.dirname(__FILE__), File.basename(__FILE__).sub(File.extname(__FILE__), ''), '*')).map do |file|
      [File.basename(file).sub(File.extname(file), '').split('_').map(&:capitalize).join.to_sym, file.sub(File.extname(file), '')]
    end.uniq.each do |klass_info|
      autoload *klass_info
      Riak.module_eval do
        autoload *klass_info
      end
    end
  end
end
