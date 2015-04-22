require 'fission-data'

module Fission
  module Data
    module Models

      # Backend service configurable item
      class ServiceConfigItem < Sequel::Model

        belongs_to :service

        # Validate account attributes
        def validate
          super
          validates_presence :name
          validates_presence :service_id
          validates_unique [:name, :service_id]
        end

        def before_destroy
          super
          self.remove_all_service_config_items
        end

      end
    end
  end
end