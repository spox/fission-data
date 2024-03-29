require 'fission-data'

module Fission
  module Data
    module Models

      # Job metadata
      class Job < Sequel::Model

        class << self

          # Provide dataset consisting of only the latest entries for
          # a given job (`message_id`)
          #
          # @return [Sequel::Dataset]
          def current_dataset
            Job.where(
              :id => current_dataset_ids
            )
          end

          # Provide dataset consisting of IDs of only latest entries
          # for a given job (`message_id`)
          #
          # @return [Sequel::Dataset]
          # @note this only returns `:id` in the dataset. if you are
          #   looking for a real dataset, use `Job.current_dataset`
          def current_dataset_ids
            Job.dataset.join_table(:left, :jobs___j2) do |j2, j|
              ({Sequel.qualify(j, :message_id) => Sequel.qualify(j2, :message_id)}) &
                (Sequel.qualify(j, :id) < Sequel.qualify(j2, :id))
            end.where(:j2__id => nil).select(:jobs__id)
          end

          # Provide model dataset with `router` unpacked from
          # the payload JSON and available for query
          #
          # @return [Sequel::Dataset]
          def dataset_with_router
            dataset_with(:collections => {:router => ['data', 'router', 'route']}).where(:id => current_dataset_ids)
          end

          # Provide model dataset with `complete` unpacked from
          # the payload JSON and available for query
          #
          # @return [Sequel::Dataset]
          def dataset_with_complete
            dataset_with(:collections => {:complete => ['complete']}).where(:id => current_dataset_ids)
          end

          # Construct customized dataset with JSON attributes extracted
          #
          # @param hash [Hash] query options
          # @option hash [Hash] :collections - {:alias_key => ['path', 'to', 'collection']
          # @option hash [Hash] :scalars - {:alias_key => ['path', 'to', 'scalar']
          # @return [Sequel::Dataset]
          # @note only one collection can be provided at this time
          def dataset_with(hash={})
            collections = hash.fetch(:collections, {})
            scalars = hash.fetch(:scalars, {})
            raise ArgumentError.new "Only one item allowed with `:collections`" if collections.size > 1
            customs = [["jobs.*", "jobs as jobs"]]
            customs += collections.map do |key, location|
              [
                "string_to_array(string_agg(trim(elm::text, '\"'), ','), ',') as #{key}",
                "json_array_elements(jobs.payload->'#{location.join("'->'")}') payload(elm)"
              ]
            end
            customs += scalars.map do |key, location|
              location = ['payload'] + location
              [
                [location.first, location.slice(1, location.size - 2).map{|x| "'#{x}'"}].flatten.compact.join('->') << "->>'#{location.last}' as #{key}",
                nil
              ]
            end
            id_restrictor = hash.fetch(:id_restrictor, current_dataset_ids)
            if(hash[:account_id])
              account_restrictor = " where jobs.account_id IN (#{[hash[:account_id]].flatten.compact.join('.')})"
              unless(hash[:id_restrictor])
                id_restrictor.where(:jobs__account_id => hash[:account_id])
              end
            end
            self.dataset.from(
              Sequel.lit(
                "(select #{customs.map(&:first).join(', ')} from #{customs.map(&:last).compact.join(', ')}" <<
                "#{account_restrictor} group by jobs.id) jobs"
              )
            ).where(:id => id_restrictor)
          end

        end

        self.add_pg_typecast_on_load_columns :payload

        many_to_one :account

        def before_save
          super
          self.payload = Sequel.pg_json(self.payload)
        end

        # Validate instance attributes
        def validate
          super
          validates_presence [:message_id, :account_id]
        end

        # @return [Fission::Utils::Smash]
        def payload
          (self.values[:payload] || {}).to_smash
        end

        # @return [String] task of job
        def task
          self.payload.fetch(:data, :router, :action, self.payload[:job])
        end

        # @return [Symbol] current job status
        def status
          unless(self.values[:status])
            if(self.payload[:error])
              :error
            else
              if(self.payload.fetch(:complete, []).include?(self.payload[:job]))
                :complete
              else
                :in_progress
              end
            end
          else
            self.values[:status].to_sym
          end
        end

        # @return [Integer] percentage of job completed
        def percent_complete
          done = self.payload.fetch(:complete, []).find_all do |j|
            !j.include?(':')
          end
          total = [done, self.payload.fetch(:data, :router, :route, [])].flatten.compact
          unless(total.empty?)
            ((done.count / total.count.to_f) * 100).to_i
          else
            -1
          end
        end

        # @return [Sequel::Dataset] events
        def events
          Event.where(:message_id => self.message_id)
        end

        # Services composing route
        #
        # @param as_models [Truthy, Falsey] return Service model instances
        # @return [Array<String>, Array<Service>]
        def route_services(as_models=false)
          if(as_models)
            (completed_services + pending_services).map do |s_name|
              Service.find_by_name(s_name)
            end.compact
          else
            completed_services + pending_services
          end
        end

        # @return [Array<String>]
        def pending_services(as_models=false)
          result = self.payload.fetch(:data, :router, :route, [])
          as_models ? result.map{|i| Service.find_by_name(i)}.compact : result
        end

        # @return [Array<String>]
        def completed_services(as_models=false)
          result = self.payload.fetch(:complete, []).find_all do |c|
            !c.include?(':')
          end
          as_models ? result.map{|i| Service.find_by_name(i)}.compact : result
        end

      end
    end
  end
end
