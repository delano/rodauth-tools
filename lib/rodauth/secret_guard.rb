# lib/rodauth/secret_guard.rb
#
# frozen_string_literal: true

require 'securerandom'

module Rodauth
  # Shared, secret-kind-parameterized logic behind the +hmac_secret_guard+ and
  # +jwt_secret_guard+ features.
  #
  # The two guard features are nearly identical; the only thing that differs is
  # the "kind" of secret they manage (+:hmac+ or +:jwt+) and the names of the
  # configuration methods that carry that kind as a prefix
  # (+hmac_secret_env_key+ vs +jwt_secret_env_key+, and so on).
  #
  # Keeping this logic in one place — and taking +kind+ as an explicit argument
  # rather than baking it into method names — is what lets both features be
  # enabled at the same time. Each feature's +post_configure+ calls into these
  # helpers with its own +kind+, so both secrets are validated at boot. When the
  # per-feature methods shared a name (the previous design), enabling both
  # guards meant one definition shadowed the other and only a single secret was
  # ever validated.
  #
  # These are plain module functions that take the Rodauth instance explicitly
  # (rather than being mixed in) so there is no method-name surface to collide
  # in the first place.
  module SecretGuard
    module_function

    # Auto-populate +<kind>_secret+ from its environment variable when it has
    # not been configured explicitly.
    #
    # The variable is read with +ENV.delete+ so the raw secret does not linger
    # in the process environment after boot. A blank (nil/empty/whitespace-only)
    # value is treated as absent and leaves the secret unset for +validate!+ to
    # handle.
    #
    # @param rodauth [Rodauth::Auth] the Rodauth instance being configured
    # @param kind [Symbol] the secret kind (+:hmac+ or +:jwt+)
    # @return [void]
    def load_from_env!(rodauth, kind)
      return unless blank?(rodauth.send(:"#{kind}_secret"))

      raw = ENV.delete(rodauth.send(:"#{kind}_secret_env_key"))
      value = raw&.strip
      return if value.nil? || value.empty?

      define_secret(rodauth, kind, value)
    end

    # Validate that +<kind>_secret+ is usable.
    #
    # In production a missing (nil/empty/whitespace-only) or too-short secret
    # raises +Rodauth::ConfigurationError+ — the guard fails closed. Outside
    # production a missing secret logs a warning and falls back to the
    # (ephemeral, per-process) development fallback.
    #
    # @param rodauth [Rodauth::Auth] the Rodauth instance being configured
    # @param kind [Symbol] the secret kind (+:hmac+ or +:jwt+)
    # @raise [Rodauth::ConfigurationError] when the secret is unusable in production
    # @return [void]
    def validate!(rodauth, kind)
      current = rodauth.send(:"#{kind}_secret")

      unless blank?(current)
        enforce_minimum_length!(rodauth, kind, current)
        return
      end

      raise Rodauth::ConfigurationError, rodauth.send(:"#{kind}_secret_missing_error") if rodauth.production?

      warn(rodauth, rodauth.send(:"#{kind}_secret_dev_warning"))
      define_secret(rodauth, kind, rodauth.send(:"development_#{kind}_secret_fallback"))
    end

    # Resolve the configured production check into a boolean.
    #
    # A Proc is evaluated in the Rodauth instance context (so it can read config
    # methods); anything else is coerced with +!!+.
    #
    # @param rodauth [Rodauth::Auth] the Rodauth instance being configured
    # @return [Boolean]
    def production?(rodauth)
      check = rodauth.send(:production_env_check)
      check.is_a?(Proc) ? rodauth.instance_exec(&check) : !!check
    end

    # Enforce +minimum_secret_length+ when it is configured (> 0).
    #
    # Only applied in production so development fallbacks and short test secrets
    # are unaffected. Disabled by default.
    #
    # @return [void]
    def enforce_minimum_length!(rodauth, kind, value)
      minimum = rodauth.send(:minimum_secret_length).to_i
      return if minimum <= 0
      return unless rodauth.production?
      return if value.to_s.strip.length >= minimum

      # Name the secret generically and cite both configuration avenues: the
      # value may have come from the env var OR from the #{kind}_secret DSL
      # method, so blaming the env key alone would mislead when a short secret
      # was configured directly.
      key = rodauth.send(:"#{kind}_secret_env_key")
      raise Rodauth::ConfigurationError,
            "#{kind.to_s.upcase} secret must be at least #{minimum} characters in production " \
            "(set via #{key} or #{kind}_secret)"
    end

    # @return [Boolean] true when the value is nil, empty, or whitespace-only
    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end

    # Redefine +<kind>_secret+ on the Rodauth subclass to return +value+.
    #
    # This mirrors how Rodauth features memoize resolved config: the auth class
    # is per-configuration and this runs once, single-threaded, at boot.
    #
    # @return [void]
    def define_secret(rodauth, kind, value)
      rodauth.class.send(:define_method, :"#{kind}_secret") { value }
    end

    # Emit a development warning via the Rodauth logger when present, otherwise
    # to stderr.
    #
    # @return [void]
    def warn(rodauth, message)
      if rodauth.respond_to?(:logger) && rodauth.logger
        rodauth.logger.warn(message)
      else
        Kernel.warn(message)
      end
    end
  end
end
