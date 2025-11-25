# spec/rodauth/features/hmac_secret_guard/hmac_secret_guard_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'

RSpec.describe 'HmacSecretGuard' do
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

  describe 'basic functionality' do
    it 'allows feature to be enabled' do
      app = create_roda_app do
        enable :hmac_secret_guard
        validate_secrets_on_configure? false
      end

      expect(app).not_to be_nil
    end

    it 'does not interfere when hmac_secret is already set' do
      app = create_roda_app do
        enable :hmac_secret_guard
        hmac_secret 'my-custom-secret-12345'
      end

      expect(app).not_to be_nil
      # Create an instance to test
      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.hmac_secret).to eq('my-custom-secret-12345')
    end
  end

  describe 'production mode validation' do
    it 'raises error when secret missing in production' do
      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError) do |error|
        expect(error.message).to include('HMAC_SECRET')
        expect(error.message).to include('production')
      end
    end

    it 'succeeds in production when secret is set' do
      app = create_roda_app do
        enable :hmac_secret_guard
        production_env_check true
        hmac_secret 'production-secret-12345'
      end

      expect(app).not_to be_nil
      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.hmac_secret).to eq('production-secret-12345')
    end

    it 'raises error with custom message' do
      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
          hmac_secret_missing_error 'CRITICAL: Secret not configured!'
        end
      end.to raise_error(Rodauth::ConfigurationError, 'CRITICAL: Secret not configured!')
    end
  end

  describe 'development mode fallback' do
    it 'warns and uses fallback when secret missing' do
      output = capture_warnings do
        app = create_roda_app do
          enable :hmac_secret_guard
          production_env_check false
        end

        expect(app).not_to be_nil
        rodauth_instance = app.rodauth.allocate
        expect(rodauth_instance.hmac_secret).to eq('dev-only-insecure-example-hmac-secret-needs-to-be-changed-in-prod')
      end

      expect(output).to include('WARNING')
      expect(output).to include('HMAC secret')
    end

    it 'uses custom development fallback' do
      output = capture_warnings do
        app = create_roda_app do
          enable :hmac_secret_guard
          production_env_check false
          development_hmac_secret_fallback 'custom-dev-secret'
        end

        expect(app).not_to be_nil
        rodauth_instance = app.rodauth.allocate
        expect(rodauth_instance.hmac_secret).to eq('custom-dev-secret')
      end

      expect(output).to include('WARNING')
    end

    it 'uses custom warning message' do
      output = capture_warnings do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check false
          hmac_secret_dev_warning 'DEV WARNING: Custom message'
        end
      end

      expect(output).to include('DEV WARNING: Custom message')
    end

    it 'does not warn when secret is set in development' do
      output = capture_warnings do
        app = create_roda_app do
          enable :hmac_secret_guard
          production_env_check false
          hmac_secret 'my-dev-secret'
        end

        expect(app).not_to be_nil
      end

      expect(output).not_to include('WARNING')
    end
  end

  describe 'environment variable loading' do
    before do
      ENV['HMAC_SECRET'] = 'env-secret-12345'
    end

    after do
      ENV.delete('HMAC_SECRET')
    end

    it 'loads secret from environment variable' do
      app = create_roda_app do
        enable :hmac_secret_guard
        production_env_check true
      end

      expect(app).not_to be_nil
      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.hmac_secret).to eq('env-secret-12345')
    end

    it 'deletes secret from ENV after loading' do
      create_roda_app do
        enable :hmac_secret_guard
        production_env_check true
      end

      expect(ENV.fetch('HMAC_SECRET', nil)).to be_nil
    end

    it 'uses custom environment variable key' do
      ENV['MY_CUSTOM_SECRET'] = 'custom-env-secret'

      app = create_roda_app do
        enable :hmac_secret_guard
        hmac_secret_env_key 'MY_CUSTOM_SECRET'
        production_env_check true
      end

      expect(app).not_to be_nil
      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.hmac_secret).to eq('custom-env-secret')
      expect(ENV.fetch('MY_CUSTOM_SECRET', nil)).to be_nil

      ENV.delete('MY_CUSTOM_SECRET')
    end

    it 'prefers explicitly set secret over environment variable' do
      app = create_roda_app do
        hmac_secret 'explicit-secret'
        enable :hmac_secret_guard
        production_env_check true
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.hmac_secret).to eq('explicit-secret')
      expect(ENV.fetch('HMAC_SECRET', nil)).to eq('env-secret-12345')
    end
  end

  describe 'production_env_check' do
    it 'uses proc for dynamic production check' do
      ENV['CUSTOM_ENV'] = 'production'

      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check proc { ENV['CUSTOM_ENV'] == 'production' }
        end
      end.to raise_error(Rodauth::ConfigurationError)

      ENV.delete('CUSTOM_ENV')
    end

    it 'uses boolean for static production check' do
      output = capture_warnings do
        app = create_roda_app do
          enable :hmac_secret_guard
          production_env_check false
        end

        expect(app).not_to be_nil
      end

      expect(output).to include('WARNING')
    end
  end

  describe 'validate_secrets_on_configure?' do
    it 'skips validation when disabled' do
      app = create_roda_app do
        enable :hmac_secret_guard
        production_env_check true
        validate_secrets_on_configure? false
      end

      expect(app).not_to be_nil
    end

    it 'validates by default' do
      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError)
    end
  end

  describe 'public methods' do
    it 'provides production? method' do
      app = create_roda_app do
        enable :hmac_secret_guard
        production_env_check true
        hmac_secret 'test-secret'
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.production?).to be true
    end

    it 'provides validate_secrets! method' do
      app = create_roda_app do
        enable :hmac_secret_guard
        validate_secrets_on_configure? false
        production_env_check true
        hmac_secret 'test-secret'
      end

      rodauth_instance = app.rodauth.allocate
      expect { rodauth_instance.validate_secrets! }.not_to raise_error
    end

    it 'validate_secrets! raises when secret missing in production' do
      app = create_roda_app do
        enable :hmac_secret_guard
        validate_secrets_on_configure? false
        production_env_check true
      end

      rodauth_instance = app.rodauth.allocate
      expect { rodauth_instance.validate_secrets! }.to raise_error(Rodauth::ConfigurationError)
    end
  end

  describe 'edge cases' do
    it 'handles empty string as missing secret' do
      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
          hmac_secret ''
        end
      end.to raise_error(Rodauth::ConfigurationError)
    end

    it 'handles nil secret' do
      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
          hmac_secret nil
        end
      end.to raise_error(Rodauth::ConfigurationError)
    end

    it 'handles empty environment variable' do
      ENV['HMAC_SECRET'] = ''

      expect do
        create_roda_app do
          enable :hmac_secret_guard
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError)

      ENV.delete('HMAC_SECRET')
    end
  end
end
