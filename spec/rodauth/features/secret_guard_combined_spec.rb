# spec/rodauth/features/secret_guard_combined_spec.rb
#
# frozen_string_literal: true

# Regression coverage for the method-name collision between hmac_secret_guard
# and jwt_secret_guard. Previously both features defined identically named
# methods (validate_secrets!, production?, warn_dev_secret); enabling both meant
# one definition shadowed the other and only a single secret was validated at
# boot. The shared Rodauth::SecretGuard logic is keyed by secret kind so each
# feature validates its own secret independently.

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'

RSpec.describe 'HmacSecretGuard + JwtSecretGuard enabled together' do
  let(:db) { Sequel.sqlite }

  after do
    db.disconnect if db
  end

  def create_roda_app(&rodauth_block)
    test_db = db

    Class.new(Roda) do
      plugin :rodauth do
        db test_db
        instance_eval(&rodauth_block) if rodauth_block
      end

      route do |r|
        r.rodauth
      end
    end
  end

  def capture_warnings
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end

  it 'validates the JWT secret even when the HMAC secret is present' do
    expect do
      create_roda_app do
        enable :hmac_secret_guard, :jwt_secret_guard
        production_env_check true
        hmac_secret 'present-hmac-secret-value'
        # jwt_secret intentionally left unset
      end
    end.to raise_error(Rodauth::ConfigurationError, /JWT/)
  end

  it 'validates the HMAC secret even when the JWT secret is present' do
    expect do
      create_roda_app do
        enable :hmac_secret_guard, :jwt_secret_guard
        production_env_check true
        jwt_secret 'present-jwt-secret-value'
        # hmac_secret intentionally left unset
      end
    end.to raise_error(Rodauth::ConfigurationError, /HMAC/)
  end

  it 'validation order does not matter (jwt enabled first)' do
    expect do
      create_roda_app do
        enable :jwt_secret_guard, :hmac_secret_guard
        production_env_check true
        jwt_secret 'present-jwt-secret-value'
        # hmac_secret intentionally left unset
      end
    end.to raise_error(Rodauth::ConfigurationError, /HMAC/)
  end

  it 'succeeds when both secrets are present in production' do
    app = create_roda_app do
      enable :hmac_secret_guard, :jwt_secret_guard
      production_env_check true
      hmac_secret 'present-hmac-secret-value'
      jwt_secret 'present-jwt-secret-value'
    end

    expect(app).not_to be_nil
    rodauth_instance = app.rodauth.allocate
    expect(rodauth_instance.hmac_secret).to eq('present-hmac-secret-value')
    expect(rodauth_instance.jwt_secret).to eq('present-jwt-secret-value')
  end

  it 'installs independent development fallbacks for both secrets' do
    app = nil
    output = capture_warnings do
      app = create_roda_app do
        enable :hmac_secret_guard, :jwt_secret_guard
        production_env_check false
      end
    end

    rodauth_instance = app.rodauth.allocate
    hmac = rodauth_instance.hmac_secret
    jwt = rodauth_instance.jwt_secret

    expect(hmac).to be_a(String)
    expect(jwt).to be_a(String)
    expect(hmac).not_to be_empty
    expect(jwt).not_to be_empty
    # Distinct per-kind fallbacks, not a single shared value
    expect(hmac).not_to eq(jwt)

    expect(output).to include('HMAC secret')
    expect(output).to include('JWT secret')
  end
end
