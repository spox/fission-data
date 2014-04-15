module Fission
  module Data
    module ModelInterface

      module User

        class << self

          def included(klass)
            klass.class_eval do
              class << self
                # List displayable attributes
                def display_attributes
                  [:username, :name]
                end

                # attributes:: Attribute hash including `:username` and `:password`
                # Attempt to locate user and authenticate
                def authenticate(attributes)
                  ident = Fission::Data::Identity.lookup(attributes[:username], :internal)
                  if(ident && ident.authenticate(attributes[:password]))
                    ident.user
                  end
                end

                # attributes:: Attribute hash
                # Create a new user instance and identity instance if applicable
                def create(attributes)
                  user = new(:username => attributes[:username])
                  if(user.save)
                    if(attributes[:provider] == :internal)
                      identity = Fission::Data::Identity.new(
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

              # Helper method to make conversion easier
              def email
                default_identity.infos['email']
              end

              # provider:: Provider symbol (:github)
              # Return oauth token for given provider
              def token_for(provider)
                identities.detect do |i|
                  i.provider && i.provider.to_sym == provider.to_sym
                end.credentials['token']
              end

              # name:: Optional account name (probably not needed until custom accounts can be created)
              # Create an account and attach it to this user as the base account
              def create_account(name=nil)
                unless(base_account)
                  act = Fission::Data::Account.new(
                    :name => name || username,
                    :owner => self
                  )
                  if(defined?(Fission::Data::Source))
                    source = Fission::Data::Source.find_or_create(:name => 'internal')
                    act.source = source
                  end
                  if(act.save)
                    self.base_account = act
                    unless(self.save)
                      raise self.errors
                    end
                  else
                    raise "Failed to create base account"
                  end
                end
              end

              # session access wrapper
              def session
                unless(self.active_session)
                  self.active_session = Fission::Data::Session.create(:user => self)
                  self.save
                end
                self.active_session
              end

              # Reset the `session_data`
              def clear_session!
                current = self.active_session
                if(current)
                  current.delete
                end
                self.active_session = Fission::Data::Session.create(:user => self)
                self.save
              end

              # Check if user is permitted (not fully implemented yet)
              def permitted?(*args)
                args.detect do |permission|
                  permissions.include?(permission)
                end
              end

              # Ensure our account wrapper is created
              def after_create
                super
                create_account
              end

              # Return the marked default identity. For now we only accept
              # github so it's super duper dumb
              def default_identity
                identities.detect{|i| (i.provider || 'wat').to_sym == :github}
              end

            end
          end
        end

      end

    end
  end
end
