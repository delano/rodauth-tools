# lib/rodauth/features/hmac_secret_guard.rb
#
# frozen_string_literal: true

require 'securerandom'
require_relative '../secret_guard'

module Rodauth
  # Automatically sets hmac_secret based on HMAC_SECRET and validates it is properly
  # configured before the application starts. This helps prevent deployment
  # errors where secret environment variables might not be set correctly,
  # particularly in production environments.
  #
  # By default, this feature checks during +post_configure+ that +hmac_secret+
  # is set to a non-blank value. In production mode, it raises a
  # ConfigurationError if the secret is missing. In development mode, it logs
  # a warning and uses a fallback development secret.
  #
  # This feature and +jwt_secret_guard+ can be enabled together. Their shared
  # logic lives in +Rodauth::SecretGuard+ and is keyed by secret kind, so each
  # secret is validated independently at boot.
  #
  # @example Basic Configuration
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #   end
  #
  # @example Customizing Production Detection (fail-safe)
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #     # Treat an unset RACK_ENV as production so a misconfigured deploy fails
  #     # closed rather than silently using the development fallback secret:
  #     production_env_check proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
  #     # Or force it:
  #     # production_env_check true
  #   end
  #
  #   # The default already fails safe: an unset RACK_ENV is treated as
  #   # production. Avoid `proc { ENV['RACK_ENV'] == 'production' }` — when the
  #   # variable is unset that returns false and silently falls back to the
  #   # insecure development secret in what is really a production deploy.
  #
  # @example Customizing Error Messages
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #     hmac_secret_missing_error 'HMAC secret must be configured in production!'
  #     hmac_secret_dev_warning 'WARNING: Using insecure development HMAC secret'
  #   end
  #
  # @example Customizing Development Fallback
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #     development_hmac_secret_fallback 'my-custom-dev-secret'
  #   end
  #
  #   # The default fallback is a random per-process value (SecureRandom.hex),
  #   # not a constant baked into source. Set an explicit value only if you need
  #   # HMAC output to be stable across restarts in development.
  #
  # @example Enforcing a Minimum Secret Length (production only)
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #     minimum_secret_length 32  # reject short secrets in production; 0 disables (default)
  #   end
  #
  # @example Disabling Validation
  #   plugin :rodauth do
  #     enable :hmac_secret_guard
  #     validate_secrets_on_configure? false
  #   end
  #
  Feature.define(:hmac_secret_guard, :HmacSecretGuard) do
    auth_value_method :hmac_secret_env_key, 'HMAC_SECRET'
    auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
    auth_value_method :validate_secrets_on_configure?, true
    auth_value_method :minimum_secret_length, 0
    # Random per-process fallback: never committed to source, and unstable across
    # restarts so it can't be mistaken for a real, persistent secret.
    auth_value_method :development_hmac_secret_fallback, SecureRandom.hex(32)

    translatable_method :hmac_secret_missing_error, 'HMAC_SECRET environment variable must be set in production'
    translatable_method :hmac_secret_dev_warning, '[rodauth] WARNING: Using default HMAC secret for development only'

    def post_configure
      super

      Rodauth::SecretGuard.load_from_env!(self, :hmac)
      validate_hmac_secret! if validate_secrets_on_configure?
    end

    auth_methods :validate_secrets!, :validate_hmac_secret!, :production?

    # Check if we're running in production environment.
    #
    # @return [Boolean] true if running in production mode based on production_env_check
    def production?
      Rodauth::SecretGuard.production?(self)
    end

    # Validate that the HMAC secret is properly configured. Raises
    # ConfigurationError in production if the secret is missing, blank, or (when
    # +minimum_secret_length+ is set) too short. In development it warns and
    # installs a fallback secret.
    #
    # This is the collision-free entry point: prefer it over +validate_secrets!+
    # when both secret guards are enabled.
    #
    # @raise [Rodauth::ConfigurationError] if hmac_secret is unusable in production
    # @return [void]
    def validate_hmac_secret!
      Rodauth::SecretGuard.validate!(self, :hmac)
    end

    # Backwards-compatible alias for +validate_hmac_secret!+.
    #
    # Note: +jwt_secret_guard+ defines a +validate_secrets!+ of its own, so when
    # both guards are enabled this name resolves to only one of them. Boot-time
    # validation does not rely on it (see +post_configure+); use
    # +validate_hmac_secret!+ for an unambiguous manual call.
    #
    # @raise [Rodauth::ConfigurationError] if hmac_secret is unusable in production
    # @return [void]
    def validate_secrets!
      validate_hmac_secret!
    end
  end
end
