require 'ostruct'
require 'fission-data'

module Fission
  module Data
    module Models

      # User data model
      class User < Sequel::Model

        # Preferred default identity
        DEFAULT_IDENTITY = 'github'

        one_to_one :active_session, :class => Session
        one_to_many :owned_accounts, :class => Account
        many_to_many :member_accounts, :class => Account, :right_key => :account_id, :join_table => 'accounts_members'
        many_to_many :managed_accounts, :class => Account, :right_key => :account_id, :join_table => 'accounts_owners'
        one_to_many :identities
        many_to_one :source
        one_to_many :tokens

        def before_save
          super
          validates_presence :source_id
          validates_unique [:username, :source_id]
        end

        # Create new instance
        # @note used for run_state initializaiton
        def initialize(*_)
          super
          @run_state = OpenStruct.new
        end

        # @return [Account] user specific account
        def base_account
          owned_accounts_dataset.where(:name => self.username).first
        end

        # @return [OpenStruct] instance cache data
        def run_state
          key = "#{self.name}_run_state".to_sym
          Thread.current[key] ||= OpenStruct.new
        end

        # Validate instance attributes
        def validate
          super
          validates_presence :username
        end

        # Ensure our account wrapper is created
        def after_create
          super
          create_account
        end

        # @return [Identity]
        def default_identity
          identities_dataset.where(:provider => DEFAULT_IDENTITY).first ||
            identities.first
        end

        # @return [NilClass, String] email
        def email
          if(default_identity)
            default_identity[:infos][:email]
          end
        end

        # @return [Array<Permission>]
        def permissions
          [self.owned_accounts,
            self.member_accounts,
            self.managed_accounts
          ].flatten.compact.map(&:active_permissions).
            flatten.compact.uniq
        end

        # @return [Array<Repository>]
        def repositories
          accounts.map(&:repositories).uniq!
        end

        # @return [Array<Account>] all accounts
        def accounts(*args)
          _accounts = [
            self.owned_accounts,
            self.managed_accounts
          ]
          unless(args.include?(:all))
            _accounts << self.member_accounts
          end
          _accounts.flatten.compact
        end

        # OAuth token for a provider
        #
        # @param provider [String]
        # @return [NilClass, String]
        def token_for(provider)
          ident = self.identities_dataset.where(:provider => provider.to_s).first
          if(ident)
            ident.credentials[:token]
          end
        end

        # Create an account and attach to this user
        #
        # @param name [String] account name
        # @return [Account]
        def create_account(name=nil)
          if(owned_accounts.empty?)
            if(default_identity)
              source = Source.find_or_create(:name => default_identity.provider)
            elsif(run_state.identity_provider)
              source = Source.find_or_create(:name => run_state.identity_provider)
            else
              source = Source.find_or_create(:name => 'internal')
            end
            add_owned_account(
              :name => name || username,
              :source_id => source.id
            )
          end
        end

        # Session data wrapper
        #
        # @return [Smash]
        def session
          unless(self.active_session)
            Session.create(:user => self, :data => Smash.new)
            self.reload
            self.save
          end
          unless(self.active_session.data[session_key])
            self.active_session.data[session_key] = Smash.new
          end
          self.active_session.data[self.session_key]
        end

        # @return [Object] key for session
        def session_key
          self.run_state.random_sec || :default
        end

        # Reset the `session_data`
        #
        # @return [Session]
        def clear_session!
          current = self.active_session
          if(current)
            current.data.delete(self.run_state.random_sec)
            current.save
          end
          self.session
        end

        # Save current session data if session exists
        #
        # @return [Session]
        def save_session
          active_session = self.active_session
          if(active_session)
            active_session.save
          end
          active_session
        end

        # Check if provided path is valid within active permission set
        #
        # @param path [String]
        # @return [TrueClass, FalseClass]
        def valid_path?(path)
          !!self.run_state.active_permissions.map(&:pattern).detect do |regex|
            regex.match(path)
          end
        end

        class << self

          # Attempt to locate user and authenticate via password
          #
          # @param attributes [Hash]
          # @option attributes [String] :username
          # @option attributes [String] :password
          # @return [NilClass, User]
          def authenticate(attributes)
            ident = Identity.lookup(attributes[:username], :internal)
            if(ident && ident.authenticate(attributes[:password]))
              ident.user
            end
          end

          # Create a new user instance and new identity if required
          #
          # @param attributes [Hash] omniauth hash
          # @return [User]
          # @note refactor this. used mainly for password auth.
          def create(attributes)
            user = new(:username => attributes[:username])
            if(attributes[:source_id])
              user.source_id = attributes[:source_id]
            end
            if(user.save)
              if(attributes[:provider] == :internal)
                identity = Identity.new(
                  :uid => attributes[:username],
                  :email => attributes[:email],
                  :provider => :internal
                )
                identity.password = attributes[:password]
                identity.password_confirmation = attributes[:password_confirmation]
                identity.user = user
                if(identity.save)
                  user.reload
                  user
                else
                  raise 'creation failed!'
                end
              end
              user
            else
              false
            end
          end

        end
      end
    end
  end
end
