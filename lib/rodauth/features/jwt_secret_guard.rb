# lib/rodauth/features/jwt_secret_guard.rb

module Rodauth
  # Automatically sets jwt_secret based on JWT_SECRET and validates it is properly
  # configured before the application starts. This helps prevent deployment
  # errors where secret environment variables might not be set correctly,
  # particularly in production environments.
  #
  # By default, this feature checks during +post_configure+ that +jwt_secret+
  # is set to a non-nil, non-empty value. In production mode, it raises a
  # ConfigurationError if the secret is missing. In development mode, it logs
  # a warning and uses a fallback development secret.
  #
  # @example Basic Configuration
  #   plugin :rodauth do
  #     enable :jwt_secret_guard
  #   end
  #
  # @example Customizing Production Detection
  #   plugin :rodauth do
  #     enable :jwt_secret_guard
  #     production_env_check proc { ENV['RACK_ENV'] == 'production' }
  #     # Or use a boolean:
  #     # production_env_check true
  #   end
  #
  # @example Customizing Error Messages
  #   plugin :rodauth do
  #     enable :jwt_secret_guard
  #     jwt_secret_missing_error 'JWT secret must be configured in production!'
  #     jwt_secret_dev_warning 'WARNING: Using insecure development JWT secret'
  #   end
  #
  # @example Customizing Development Fallback
  #   plugin :rodauth do
  #     enable :jwt_secret_guard
  #     development_jwt_secret_fallback 'my-custom-dev-secret'
  #   end
  #
  # @example Disabling Validation
  #   plugin :rodauth do
  #     enable :jwt_secret_guard
  #     validate_secrets_on_configure? false
  #   end
  #
  Feature.define(:jwt_secret_guard, :JwtSecretGuard) do
    auth_value_method :jwt_secret_env_key, 'JWT_SECRET'
    auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
    auth_value_method :validate_secrets_on_configure?, true
    auth_value_method :development_jwt_secret_fallback, 'dev-only-insecure-example-jwt-secret-needs-to-be-changed-in-prod'

    # Make jwt_secret configurable (if not already provided by jwt feature)
    auth_value_method :jwt_secret, nil

    translatable_method :jwt_secret_missing_error, 'JWT_SECRET environment variable must be set in production'
    translatable_method :jwt_secret_dev_warning, '[rodauth] WARNING: Using default JWT secret for development only'

    def post_configure
      super

      # Auto-set jwt_secret if not already set
      if jwt_secret.nil? || (jwt_secret.respond_to?(:empty?) && jwt_secret.empty?)
        env_value = ENV.delete(jwt_secret_env_key)
        self.class.send(:define_method, :jwt_secret) { env_value } if env_value && !env_value.empty?
      end

      validate_secrets! if validate_secrets_on_configure?
    end

    auth_methods :validate_secrets!, :production?

    # Check if we're running in production environment.
    #
    # @return [Boolean] true if running in production mode based on production_env_check
    def production?
      case v = production_env_check
      when Proc
        instance_exec(&v)
      else
        !!v
      end
    end

    # Validate that JWT secret is properly configured.
    # Raises ConfigurationError in production if secret is missing.
    # In development, logs a warning and sets a fallback secret.
    #
    # @raise [Rodauth::ConfigurationError] if jwt_secret is missing in production
    # @return [void]
    def validate_secrets!
      # Get the current jwt_secret value (may be nil)
      current_secret = jwt_secret

      # Return early if secret is present
      return unless current_secret.nil? || (current_secret.respond_to?(:empty?) && current_secret.empty?)
      raise Rodauth::ConfigurationError, jwt_secret_missing_error if production?

      # In development, warn and set a fallback
      warn_dev_secret
      self.class.send(:define_method, :jwt_secret) { development_jwt_secret_fallback }
    end

    private

    # Warn about using development secret.
    # Logs to logger if available, otherwise to stderr.
    #
    # @return [void]
    def warn_dev_secret
      if respond_to?(:logger) && logger
        logger.warn(jwt_secret_dev_warning)
      else
        warn(jwt_secret_dev_warning)
      end
    end
  end
end
