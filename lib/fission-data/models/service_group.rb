require 'fission-data'

module Fission
  module Data
    module Models

      # Grouping of services
      class ServiceGroup < Sequel::Model

        many_to_many :product_features
        many_to_many :services

        # Validate instance attributes
        def validate
          super
          validates_presence :name
          validates_unique :name
        end

        def before_destroy
          super
        end

      end
    end
  end
end
