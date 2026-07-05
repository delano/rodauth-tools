# lib/rodauth/features/account_id_obfuscation.rb
#
# frozen_string_literal: true

require_relative '../tools/account_id_cipher' unless defined?(Rodauth::Tools::AccountIdCipher)
require_relative '../secret_guard' unless defined?(Rodauth::SecretGuard)

module Rodauth
  # Obfuscates the numeric account id that Rodauth otherwise leaks in plaintext
  # inside email-link tokens (e.g. +/verify-account?key=2_...+) and, optionally,
  # the remember-me cookie. The id is replaced by a fixed-width, URL-safe,
  # non-sequential token: a one-character non-digit VERSION tag followed by the
  # 13-char output of {Rodauth::Tools::AccountIdCipher} (keyed format-preserving
  # encryption). No database schema change is required; the integer primary key
  # is used everywhere internally and only the value crossing the network is
  # obfuscated.
  #
  # It wraps the two email-token chokepoints in +email_base+ (+token_param_value+
  # to encode, +account_from_key+ to decode), which together cover ALL email-link
  # features: verify_account, reset_password, email_auth, verify_login_change and
  # lockout/unlock. It deliberately does NOT touch the lower-level +split_token+/
  # +convert_token_id+, so other token consumers (e.g. jwt_refresh) are unaffected.
  #
  # This is deterministic pseudonymisation, NOT access control or encryption of
  # confidential data: the same id always maps to the same token, and the token's
  # authority is unchanged (the email HMAC still gates the request after the id is
  # swapped back to the real Integer). Applies to integer/bigint primary keys.
  #
  # The VERSION tag makes obfuscated tokens deterministically distinguishable from
  # legacy decimal ids (Rodauth ids are always digits, never a letter), so legacy
  # links/cookies pass through untouched. It also selects the secret, enabling
  # config-driven key rotation via +account_id_obfuscation_previous_secrets+.
  #
  # This feature shares its ENV-loading and production-detection plumbing with
  # +hmac_secret_guard+/+jwt_secret_guard+ via +Rodauth::SecretGuard+ (see
  # +production_env_check+ and +validate_secrets_on_configure?+ below, which are
  # the same config methods those two guards expose). It keeps its own
  # always-on 32-byte minimum, though: {Rodauth::Tools::AccountIdCipher} hard-requires
  # that floor regardless of environment, unlike the guards' opt-in, production-only
  # +minimum_secret_length+.
  #
  # @example
  #   plugin :rodauth do
  #     enable :login, :verify_account, :remember, :account_id_obfuscation
  #     # ACCOUNT_ID_SECRET must be set (>= 32 bytes) in production
  #   end
  #
  # @example Development / custom secret source
  #   plugin :rodauth do
  #     enable :account_id_obfuscation
  #     account_id_obfuscation_secret_env_key 'MY_ID_SECRET'
  #     account_id_obfuscation_remember_cookie? false
  #   end
  Feature.define(:account_id_obfuscation, :AccountIdObfuscation) do
    # email_base owns the two chokepoints we wrap; depending on it guarantees it
    # is loaded and sits lower in the ancestor chain (so our +super+ resolves).
    depends :email_base

    auth_value_method :account_id_obfuscation_secret, nil
    auth_value_method :account_id_obfuscation_secret_env_key, 'ACCOUNT_ID_SECRET'
    auth_value_method :account_id_obfuscation_key_version, 'A' # single non-digit char
    auth_value_method :account_id_obfuscation_previous_secrets, {}.freeze # {ver_char => old_secret}, decode-only
    auth_value_method :account_id_obfuscation_remember_cookie?, true
    # Shared with hmac_secret_guard/jwt_secret_guard (same config method, same
    # fail-safe default): an unset RACK_ENV is treated as production. Avoid
    # `proc { ENV['RACK_ENV'] == 'production' }` — when the variable is unset
    # that returns false and silently falls back to the insecure development
    # secret in what is really a production deploy.
    auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
    # Shared with hmac_secret_guard/jwt_secret_guard: gates whether post_configure
    # calls the boot-time validator at all.
    auth_value_method :validate_secrets_on_configure?, true
    # Fixed (not random-per-process, unlike the guards' SecureRandom.hex fallback):
    # obfuscated tokens must stay stable across restarts within a single
    # development process' lifetime for links/cookies minted before a restart to
    # keep decoding, and this feature has no server-side session to smooth that
    # over. Still a placeholder — change it, or better, set ACCOUNT_ID_SECRET.
    auth_value_method :development_account_id_obfuscation_secret_fallback,
                      'dev-only-insecure-account-id-obfuscation-secret-please-change-me'

    translatable_method :account_id_obfuscation_secret_missing_error,
                        'ACCOUNT_ID_SECRET environment variable must be set in production'
    translatable_method :account_id_obfuscation_secret_too_short_error,
                        'account id obfuscation secret must be at least 32 bytes'
    translatable_method :account_id_obfuscation_key_version_error,
                        'account_id_obfuscation_key_version must be a single non-digit character'
    translatable_method :account_id_obfuscation_secret_dev_warning,
                        '[rodauth] WARNING: Using default account id obfuscation secret for development only'

    # post_configure runs on a throwaway instance, so cache the version=>cipher
    # map lazily per runtime instance rather than in an instance ivar.
    auth_cached_method :account_id_ciphers

    auth_methods :obfuscate_account_id, :deobfuscate_account_id, :production?,
                 :validate_secrets!, :validate_account_id_obfuscation_secret!

    def post_configure
      super

      load_account_id_secret_from_env
      validate_key_version!
      validate_account_id_obfuscation_secret! if validate_secrets_on_configure?

      install_remember_cookie_obfuscation if account_id_obfuscation_remember_cookie? && features.include?(:remember)
    end

    # ---- email-token chokepoints (plain overrides; email_base is a dependency,
    #      so +super+ always resolves, and internal_request delegates through) ----

    # Encode the id in the outgoing email link. Wraps email_base's token
    # ("<id><sep><hmac>") and rewrites only the id segment, staying decoupled from
    # email_base's exact composition.
    def token_param_value(key)
      original = super
      return original if account_id.nil?

      _id, separator, remainder = original.partition(token_separator)
      remainder.empty? ? original : "#{obfuscate_account_id(account_id)}#{separator}#{remainder}"
    end

    # Decode the id segment of an incoming token before email_base parses it.
    # A legacy plaintext token (or any non-token) deobfuscates to nil and passes
    # through unchanged, so in-flight links keep working.
    def account_from_key(token, status_id = nil, &)
      if token.is_a?(String)
        segment, separator, remainder = token.partition(token_separator)
        if !remainder.empty? && (real_id = deobfuscate_account_id(segment))
          token = "#{real_id}#{separator}#{remainder}"
        end
      end

      super
    end

    # ---- public API ----

    # @return [String] version-tagged obfuscated form of an account id
    def obfuscate_account_id(id)
      version = account_id_obfuscation_key_version
      "#{version}#{account_id_ciphers.fetch(version).encode(id)}"
    end

    # @return [Integer, nil] the real id, or nil if +segment+ is not one of our
    #   tokens (legacy decimal id, unknown version, wrong width, or bad chars)
    def deobfuscate_account_id(segment)
      return nil unless segment.is_a?(String) &&
                        segment.length == 1 + Rodauth::Tools::AccountIdCipher::WIDTH

      cipher = account_id_ciphers[segment[0]] or return nil

      cipher.decode(segment[1..])
    end

    # Check if we're running in production environment.
    #
    # Delegates to the same +Rodauth::SecretGuard.production?+ that
    # +hmac_secret_guard+/+jwt_secret_guard+ use, so behavior is identical
    # whichever guard's copy of this method happens to win when several are
    # enabled together (see +validate_secrets!+ below for why that collision
    # matters more for validation than for this read-only check).
    #
    # @return [Boolean] true if running in production mode based on production_env_check
    def production?
      Rodauth::SecretGuard.production?(self)
    end

    # Validate that the account-id obfuscation secret(s) are properly
    # configured. Raises ConfigurationError in production if the current
    # secret is missing or blank. Always (in every environment) raises if the
    # current secret, or any +account_id_obfuscation_previous_secrets+ entry,
    # is present but shorter than +AccountIdCipher::MIN_SECRET_BYTES+ — unlike
    # +minimum_secret_length+ on the sibling guards, this floor is not
    # opt-in/production-only, because {Rodauth::Tools::AccountIdCipher} raises
    # ArgumentError below it regardless of environment. In development, a
    # missing current secret warns and installs a fallback.
    #
    # This is the collision-free entry point: prefer it over +validate_secrets!+
    # when this feature is co-enabled with +hmac_secret_guard+/+jwt_secret_guard+
    # (see +post_configure+, which calls this method by name so boot-time
    # validation never depends on which +validate_secrets!+ wins the MRO).
    #
    # @raise [Rodauth::ConfigurationError] if the current or a previous secret is unusable
    # @return [void]
    def validate_account_id_obfuscation_secret!
      secret = account_id_obfuscation_secret

      if Rodauth::SecretGuard.blank?(secret)
        raise Rodauth::ConfigurationError, account_id_obfuscation_secret_missing_error if Rodauth::SecretGuard.production?(self)

        warn_dev_account_id_secret
        fallback = development_account_id_obfuscation_secret_fallback
        self.class.send(:define_method, :account_id_obfuscation_secret) { fallback }
        secret = fallback
      end

      too_short = ->(value) { value.to_s.bytesize < Rodauth::Tools::AccountIdCipher::MIN_SECRET_BYTES }
      if too_short.call(secret) || account_id_obfuscation_previous_secrets.values.any?(&too_short)
        raise Rodauth::ConfigurationError, account_id_obfuscation_secret_too_short_error
      end

      # Force the version=>cipher map to build now so any other
      # AccountIdCipher.new failure (e.g. a future stricter check) also fails
      # closed at boot instead of lazily on first encode/decode.
      begin
        account_id_ciphers
      rescue ArgumentError => e
        raise Rodauth::ConfigurationError, e.message
      end
    end

    # Backwards-compatible alias for +validate_account_id_obfuscation_secret!+.
    #
    # Note: +hmac_secret_guard+ and +jwt_secret_guard+ each define a
    # +validate_secrets!+ of their own, so when this feature is co-enabled with
    # either guard this name resolves to only one of them — collision-prone;
    # not for boot. Boot-time validation does not rely on it (see
    # +post_configure+); use +validate_account_id_obfuscation_secret!+ for an
    # unambiguous manual call.
    #
    # @raise [Rodauth::ConfigurationError] if the current or a previous secret is unusable
    # @return [void]
    def validate_secrets!
      validate_account_id_obfuscation_secret!
    end

    private

    # Backing method for the +account_id_ciphers+ auth_cached_method: a
    # {version_char => AccountIdCipher} map. The current key_version is always
    # present; previous secrets are added for decode-only rotation support.
    def _account_id_ciphers
      map = {}
      account_id_obfuscation_previous_secrets.each do |version, old_secret|
        map[version.to_s] = Rodauth::Tools::AccountIdCipher.new(old_secret)
      end
      map[account_id_obfuscation_key_version] =
        Rodauth::Tools::AccountIdCipher.new(account_id_obfuscation_secret)
      map
    end

    # Consume ACCOUNT_ID_SECRET from ENV (read + delete for security), unless an
    # explicit secret was configured. Delegates to the same helper the sibling
    # guards use, so a whitespace-only env value is treated as absent exactly
    # like theirs.
    def load_account_id_secret_from_env
      Rodauth::SecretGuard.load_from_env!(self, :account_id_obfuscation)
    end

    # The backward-compat guarantee rests on every version tag (current AND any
    # +account_id_obfuscation_previous_secrets+ key) being a single, unique,
    # non-digit char distinct from the separators; fail fast otherwise. A
    # digit would be ambiguous with a legacy decimal id, and a duplicate would
    # mean two secrets claim the same version, making rotation nondeterministic.
    def validate_key_version!
      versions = [account_id_obfuscation_key_version] + account_id_obfuscation_previous_secrets.keys
      versions.each { |version| validate_version_char!(version) }

      return if versions.tally.values.all? { |count| count == 1 }

      raise Rodauth::ConfigurationError, account_id_obfuscation_key_version_error
    end

    def validate_version_char!(version)
      valid = version.is_a?(String) && version.length == 1 &&
              version !~ /\d/ && version != token_separator && version != '_'

      raise Rodauth::ConfigurationError, account_id_obfuscation_key_version_error unless valid
    end

    # Wrap the remember cookie so the id segment is obfuscated on the way out and
    # restored on the way back in. remember.rb hardcodes '_' (not token_separator)
    # as the id/key delimiter and splits with limit 2, so an HMAC key containing
    # '_' stays intact and our version-tagged id (never contains '_', never starts
    # with a digit) is safe. Legacy numeric cookies deobfuscate to nil -> passthrough.
    #
    # Installed directly on the Auth class (not as an ordinary module method) so
    # the wrapper wins regardless of the order in which +remember+ and this
    # feature are enabled: a method defined on the class itself always takes
    # precedence over the included feature modules, whereas an ordinary module
    # method would be shadowed by +remember+'s own +_set_/_get_remember_cookie+
    # whenever this feature is enabled BEFORE +remember+ (silently leaving the
    # cookie un-obfuscated).
    #
    # +internal_request+ re-runs +post_configure+ on an internally-created
    # subclass of the already-configured Auth class. We must NOT re-install there:
    # a second override on the subclass would resolve its +super+ to the parent
    # class's override (double-obfuscating the id and crashing on
    # +Integer("A...")+) instead of to remember.rb. Skipping the subclass leaves
    # it inheriting the single parent-class wrapper for +_set_remember_cookie+,
    # while +internal_request+'s own +_get_remember_cookie+ (reading the request
    # param) still wins for internal requests since it sits higher in that
    # subclass's ancestry.
    def install_remember_cookie_obfuscation
      return if defined?(Rodauth::InternalRequestMethods) && is_a?(Rodauth::InternalRequestMethods)

      self.class.send(:define_method, :_set_remember_cookie) do |account_id, remember_key_value, deadline|
        super(obfuscate_account_id(account_id), remember_key_value, deadline)
      end

      self.class.send(:define_method, :_get_remember_cookie) do
        raw = super()
        next raw unless raw.is_a?(String)

        segment, _sep, remainder = raw.partition('_')
        !remainder.empty? && (real_id = deobfuscate_account_id(segment)) ? "#{real_id}_#{remainder}" : raw
      end
    end

    def warn_dev_account_id_secret
      if respond_to?(:logger) && logger
        logger.warn(account_id_obfuscation_secret_dev_warning)
      else
        warn(account_id_obfuscation_secret_dev_warning)
      end
    end
  end
end
