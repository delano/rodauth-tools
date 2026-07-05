# lib/rodauth/features/account_id_obfuscation.rb
#
# frozen_string_literal: true

require_relative '../tools/account_id_cipher' unless defined?(Rodauth::Tools::AccountIdCipher)

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
    auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
    auth_value_method :validate_secrets_on_configure?, true
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

    auth_methods :obfuscate_account_id, :deobfuscate_account_id, :production?, :validate_secrets!

    def post_configure
      super

      load_account_id_secret_from_env
      validate_key_version!
      validate_secrets! if validate_secrets_on_configure?

      # Remember's cookie read path (remembered_session_id -> _get_remember_cookie)
      # resolves via full MRO, so our override must sit at the top of the chain
      # regardless of enable order; installing on the subclass guarantees that and
      # keeps the wiring conditional. (Same idiom as external_identity's
      # account_select wrapper.)
      install_remember_cookie_obfuscation if account_id_obfuscation_remember_cookie? && features.include?(:remember)
    end

    # ---- email-token chokepoints (plain overrides; email_base is a dependency,
    #      so +super+ always resolves, and internal_request delegates through) ----

    # Encode the id in the outgoing email link. Wraps email_base's token
    # ("<id><sep><hmac>") and rewrites only the id segment, staying decoupled from
    # email_base's exact composition.
    def token_param_value(key)
      original = super
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

    def production?
      case v = production_env_check
      when Proc then instance_exec(&v)
      else !!v
      end
    end

    # Ensure a usable secret is present (mirrors hmac_secret_guard): require it in
    # production, warn + fall back in development, and always reject a
    # present-but-too-short secret in either environment.
    def validate_secrets!
      secret = account_id_obfuscation_secret

      if secret.nil? || secret.to_s.empty?
        raise Rodauth::ConfigurationError, account_id_obfuscation_secret_missing_error if production?

        warn_dev_account_id_secret
        fallback = development_account_id_obfuscation_secret_fallback
        self.class.send(:define_method, :account_id_obfuscation_secret) { fallback }
        secret = fallback
      end

      return unless secret.to_s.bytesize < Rodauth::Tools::AccountIdCipher::MIN_SECRET_BYTES

      raise Rodauth::ConfigurationError, account_id_obfuscation_secret_too_short_error
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
    # explicit secret was configured.
    def load_account_id_secret_from_env
      secret = account_id_obfuscation_secret
      return unless secret.nil? || secret.to_s.empty?

      env_value = ENV.delete(account_id_obfuscation_secret_env_key)
      return unless env_value && !env_value.empty?

      self.class.send(:define_method, :account_id_obfuscation_secret) { env_value }
    end

    # The backward-compat guarantee rests on the version tag being a single
    # non-digit char distinct from the separators; fail fast otherwise.
    def validate_key_version!
      version = account_id_obfuscation_key_version
      valid = version.is_a?(String) && version.length == 1 &&
              version !~ /\d/ && version != token_separator && version != '_'

      raise Rodauth::ConfigurationError, account_id_obfuscation_key_version_error unless valid
    end

    # Wrap the remember cookie. remember.rb hardcodes '_' (not token_separator)
    # as the id/key delimiter and splits with limit 2, so an HMAC key containing
    # '_' stays intact and our version-tagged id (never contains '_', never starts
    # with a digit) is safe. Legacy numeric cookies deobfuscate to nil -> passthrough.
    def install_remember_cookie_obfuscation
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
