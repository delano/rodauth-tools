# spec/rodauth/features/account_id_obfuscation/account_id_obfuscation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'

RSpec.describe 'AccountIdObfuscation' do
  let(:db) do
    d = Sequel.sqlite
    d.create_table(:accounts) do
      primary_key :id
      String :email, null: false
      Integer :status_id, default: 2
    end
    d.create_table(:account_remember_keys) do
      foreign_key :id, :accounts, primary_key: true, type: :Bignum
      String :key, null: false
      DateTime :deadline
    end
    d[:accounts].insert(email: 'user@example.com', status_id: 2) # id = 1
    d
  end

  after { db&.disconnect }

  def create_roda_app(&rodauth_block)
    test_db = db

    Class.new(Roda) do
      plugin :rodauth do
        db test_db
        instance_eval(&rodauth_block) if rodauth_block
      end

      route(&:rodauth)
    end
  end

  def default_app
    create_roda_app do
      enable :login, :verify_account, :account_id_obfuscation
      hmac_secret 'h' * 32
      account_id_obfuscation_secret 'a' * 40
      production_env_check false
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

  # Stubs +response+/+request+ on a Rodauth instance so +_set_remember_cookie+
  # can run outside a real HTTP cycle. Returns the Hash that
  # Rack::Utils.set_cookie_header! writes into, keyed by header name.
  def stub_cookie_write(rodauth)
    headers = {}
    rodauth.define_singleton_method(:response) { Struct.new(:headers).new(headers) }
    rodauth.define_singleton_method(:request) { Struct.new(:ssl?).new(false).tap { |s| def s.ssl? = false } }
    headers
  end

  describe 'enabling the feature' do
    it 'builds an app with the feature enabled' do
      app = default_app
      expect(app.rodauth.features).to include(:account_id_obfuscation)
    end

    it 'auto-enables its email_base dependency' do
      app = create_roda_app do
        enable :account_id_obfuscation
        account_id_obfuscation_secret 'a' * 40
        production_env_check false
      end
      expect(app.rodauth.features).to include(:email_base)
    end
  end

  describe '#obfuscate_account_id / #deobfuscate_account_id' do
    let(:rodauth) { default_app.rodauth.allocate }

    it 'round-trips an id' do
      token = rodauth.obfuscate_account_id(1)
      expect(rodauth.deobfuscate_account_id(token)).to eq(1)
    end

    it 'prefixes the token with the version tag and is 14 chars wide' do
      token = rodauth.obfuscate_account_id(1)
      expect(token).to start_with('A')
      expect(token.length).to eq(1 + Rodauth::Tools::AccountIdCipher::WIDTH)
    end

    it 'does not leak the plaintext id' do
      expect(rodauth.obfuscate_account_id(1)).not_to include('1')
    end

    it 'returns nil for a legacy decimal id segment' do
      expect(rodauth.deobfuscate_account_id('1')).to be_nil
    end

    it 'returns nil for a 13-digit decimal id (the previously-ambiguous case)' do
      expect(rodauth.deobfuscate_account_id('1234567890123')).to be_nil
    end

    it 'returns nil for nil and non-token garbage' do
      expect(rodauth.deobfuscate_account_id(nil)).to be_nil
      expect(rodauth.deobfuscate_account_id('not-a-token!!')).to be_nil
    end

    it 'returns nil for a token carrying an unknown version tag' do
      token = rodauth.obfuscate_account_id(1)
      tampered = "Z#{token[1..]}"
      expect(rodauth.deobfuscate_account_id(tampered)).to be_nil
    end
  end

  describe 'email link obfuscation (via real email_base)' do
    let(:rodauth) do
      r = default_app.rodauth.allocate
      r.instance_variable_set(:@account, { id: 1, email: 'user@example.com', status_id: 2 })
      r
    end

    it 'obfuscates the id segment of the outgoing token' do
      link = rodauth.send(:token_param_value, 'rawkey')
      segment = link.split('_', 2).first
      expect(segment).to eq(rodauth.obfuscate_account_id(1))
      expect(link).not_to start_with('1_')
    end

    it 'decodes an obfuscated token back to the account on consume' do
      link = rodauth.send(:token_param_value, 'rawkey')
      loaded = rodauth.send(:account_from_key, link) { |id| id == 1 ? 'rawkey' : nil }
      expect(loaded[:id]).to eq(1)
    end

    it 'rejects an obfuscated token whose key does not match' do
      link = rodauth.send(:token_param_value, 'rawkey')
      loaded = rodauth.send(:account_from_key, link) { |_id| 'wrongkey' }
      expect(loaded).to be_nil
    end

    it 'still resolves a legacy plaintext token (backward compatibility)' do
      legacy = "1_#{rodauth.send(:convert_email_token_key, "rawkey")}"
      loaded = rodauth.send(:account_from_key, legacy) { |id| id == 1 ? 'rawkey' : nil }
      expect(loaded[:id]).to eq(1)
    end

    it 'passes a separator-less token through to base without obfuscation (no crash)' do
      # No separator => decode step is skipped and base rejects it as malformed.
      expect(rodauth.send(:account_from_key, 'no-separator-here') { |_id| 'x' }).to be_nil
    end
  end

  describe 'key rotation via previous_secrets' do
    let(:rodauth) do
      create_roda_app do
        enable :login, :verify_account, :account_id_obfuscation
        hmac_secret 'h' * 32
        account_id_obfuscation_secret 'b' * 40 # current, version 'B'
        account_id_obfuscation_key_version 'B'
        account_id_obfuscation_previous_secrets({ 'A' => 'a' * 40 }) # retired, version 'A'
        production_env_check false
      end.rodauth.allocate
    end

    it 'mints new tokens under the current version tag' do
      expect(rodauth.obfuscate_account_id(1)).to start_with('B')
    end

    it 'still decodes a token minted under a previous secret/version' do
      old_cipher = Rodauth::Tools::AccountIdCipher.new('a' * 40)
      old_token = "A#{old_cipher.encode(1)}"
      expect(rodauth.deobfuscate_account_id(old_token)).to eq(1)
    end
  end

  describe 'rotation input validation (Findings #4, #5)' do
    it 'raises for a digit previous-version key' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_previous_secrets({ '1' => 'b' * 40 })
          production_env_check false
        end
      end.to raise_error(Rodauth::ConfigurationError, /single non-digit/)
    end

    it 'raises when a previous-version key collides with the current version' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_key_version 'A' # default, spelled out for clarity
          account_id_obfuscation_previous_secrets({ 'A' => 'b' * 40 })
          production_env_check false
        end
      end.to raise_error(Rodauth::ConfigurationError, /single non-digit/)
    end

    it 'raises when a previous secret is shorter than 32 bytes, at boot rather than lazily' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_key_version 'B'
          account_id_obfuscation_previous_secrets({ 'A' => 'too-short' })
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError, /at least 32 bytes/)
    end

    it 'accepts multiple distinct previous-version keys without a false-positive collision' do
      rodauth = create_roda_app do
        enable :account_id_obfuscation
        account_id_obfuscation_secret 'a' * 40
        account_id_obfuscation_key_version 'C'
        account_id_obfuscation_previous_secrets({ 'A' => 'x' * 40, 'B' => 'y' * 40 })
        production_env_check false
      end.rodauth.allocate

      expect(rodauth.obfuscate_account_id(1)).to start_with('C')
    end

    it 'still deobfuscates a 14-digit legacy id to nil under a valid config' do
      rodauth = default_app.rodauth.allocate
      expect(rodauth.deobfuscate_account_id('12345678901234')).to be_nil
    end
  end

  describe 'key version validation' do
    it 'raises for a digit version tag' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_key_version '1'
          production_env_check false
        end
      end.to raise_error(Rodauth::ConfigurationError, /single non-digit/)
    end

    it 'raises for a multi-character version tag' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_key_version 'AB'
          production_env_check false
        end
      end.to raise_error(Rodauth::ConfigurationError, /single non-digit/)
    end

    it 'raises for an underscore version tag' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'a' * 40
          account_id_obfuscation_key_version '_'
          production_env_check false
        end
      end.to raise_error(Rodauth::ConfigurationError, /single non-digit/)
    end
  end

  describe 'secret lifecycle' do
    it 'raises in production when the secret is missing' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError, /ACCOUNT_ID_SECRET/)
    end

    it 'raises in production when the secret is present but blank (whitespace-only)' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret ' ' * 40
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError, /ACCOUNT_ID_SECRET/)
    end

    it 'raises when the secret is present but shorter than 32 bytes' do
      expect do
        create_roda_app do
          enable :account_id_obfuscation
          account_id_obfuscation_secret 'too-short'
          production_env_check true
        end
      end.to raise_error(Rodauth::ConfigurationError, /at least 32 bytes/)
    end

    it 'warns and falls back to a dev secret when missing in development' do
      output = capture_warnings do
        app = create_roda_app do
          enable :account_id_obfuscation
          production_env_check false
        end
        # feature still works with the fallback
        expect(app.rodauth.allocate.obfuscate_account_id(1)).to start_with('A')
      end
      expect(output).to include('WARNING')
    end

    it 'loads the secret from ENV and deletes it afterwards' do
      ENV['ACCOUNT_ID_SECRET'] = 'e' * 40
      app = create_roda_app do
        enable :account_id_obfuscation
        production_env_check true
      end
      expect(app.rodauth.allocate.deobfuscate_account_id(app.rodauth.allocate.obfuscate_account_id(1))).to eq(1)
      expect(ENV.fetch('ACCOUNT_ID_SECRET', nil)).to be_nil
    ensure
      ENV.delete('ACCOUNT_ID_SECRET')
    end

    it 'uses a custom ENV key' do
      ENV['MY_ID_SECRET'] = 'e' * 40
      app = create_roda_app do
        enable :account_id_obfuscation
        account_id_obfuscation_secret_env_key 'MY_ID_SECRET'
        production_env_check true
      end
      expect(app.rodauth.allocate.obfuscate_account_id(1)).to start_with('A')
      expect(ENV.fetch('MY_ID_SECRET', nil)).to be_nil
    ensure
      ENV.delete('MY_ID_SECRET')
    end

    it 'prefers an explicitly-set secret over the ENV var' do
      ENV['ACCOUNT_ID_SECRET'] = 'e' * 40
      app = create_roda_app do
        enable :account_id_obfuscation
        account_id_obfuscation_secret 'x' * 40
        production_env_check true
      end
      expect(app).not_to be_nil
      expect(ENV.fetch('ACCOUNT_ID_SECRET', nil)).to eq('e' * 40)
    ensure
      ENV.delete('ACCOUNT_ID_SECRET')
    end

    it 'skips validation when validate_secrets_on_configure? is false' do
      app = create_roda_app do
        enable :account_id_obfuscation
        production_env_check true
        validate_secrets_on_configure? false
      end
      expect(app).not_to be_nil
    end
  end

  describe 'remember cookie obfuscation' do
    def remember_app(obfuscate_cookie: true)
      create_roda_app do
        enable :login, :remember, :account_id_obfuscation
        hmac_secret 'h' * 32
        account_id_obfuscation_secret 'a' * 40
        account_id_obfuscation_remember_cookie? obfuscate_cookie
        production_env_check false
      end
    end

    it 'round-trips: writes an obfuscated cookie, then reads the real id back out of it' do
      r = remember_app.rodauth.allocate
      headers = stub_cookie_write(r)

      r.send(:_set_remember_cookie, 1, 'remkey', Time.now + 1000)
      raw_value = headers.values.join[/_remember=([^;]+)/, 1]
      expect(raw_value).not_to be_nil
      expect(raw_value).to start_with(r.obfuscate_account_id(1))

      fake_request = Struct.new(:cookies).new({ '_remember' => raw_value })
      r.define_singleton_method(:request) { fake_request }

      # remember.rb's own cookie value is "<id>_<converted key>"; the key half
      # is opaque here (an HMAC, not the raw value) -- only the id half is
      # ours to deobfuscate, so compare against the same conversion.
      expect(r.send(:_get_remember_cookie)).to eq("1_#{r.send(:convert_token_key, "remkey")}")
    end

    it 'with the toggle off, writes a byte-identical cookie header to stock remember' do
      deadline = Time.now + 1000

      off = remember_app(obfuscate_cookie: false).rodauth.allocate
      off_headers = stub_cookie_write(off)
      off.send(:_set_remember_cookie, 1, 'remkey', deadline)

      stock = create_roda_app do
        enable :login, :remember
        hmac_secret 'h' * 32
      end.rodauth.allocate
      stock_headers = stub_cookie_write(stock)
      stock.send(:_set_remember_cookie, 1, 'remkey', deadline)

      expect(off_headers).to eq(stock_headers)
    end

    # Regression test: the remember-cookie wrapper is installed directly on the
    # Auth class so it wins no matter where account_id_obfuscation sits relative
    # to remember in the enable list. An earlier design used ordinary module
    # methods, which remember's own _set_remember_cookie silently shadowed (thus
    # skipping obfuscation) whenever this feature was enabled BEFORE remember.
    [%i[login remember account_id_obfuscation],
     %i[account_id_obfuscation login remember]].each do |feature_order|
      it "obfuscates the remember cookie regardless of enable order (#{feature_order.join(", ")})" do
        app = create_roda_app do
          enable(*feature_order)
          hmac_secret 'h' * 32
          account_id_obfuscation_secret 'a' * 40
          production_env_check false
        end
        r = app.rodauth.allocate
        headers = stub_cookie_write(r)

        r.send(:_set_remember_cookie, 1, 'remkey', Time.now + 1000)
        raw_value = headers.values.join[/_remember=([^;]+)/, 1]

        expect(raw_value).not_to be_nil
        expect(raw_value).to start_with(r.obfuscate_account_id(1))
        expect(raw_value).not_to start_with('1_') # never the plaintext id
      end
    end

    it 'does not install the cookie overrides when remember is not enabled' do
      # default_app enables account_id_obfuscation WITHOUT remember, so
      # install_remember_cookie_obfuscation is never called and the class-level
      # overrides never exist -- nothing to wrap, no accidental interference.
      auth = default_app.rodauth
      expect(auth.private_instance_methods).not_to include(:_set_remember_cookie, :_get_remember_cookie)
    end

    it 'decodes the id segment of an obfuscated cookie on read' do
      r = remember_app.rodauth.allocate
      obfuscated = "#{r.obfuscate_account_id(1)}_HMAC_WITH_UNDERSCORES"
      fake_request = Struct.new(:cookies).new({ '_remember' => obfuscated })
      r.define_singleton_method(:request) { fake_request }

      expect(r.send(:_get_remember_cookie)).to eq('1_HMAC_WITH_UNDERSCORES')
    end

    it 'passes a legacy numeric cookie through unchanged on read' do
      r = remember_app.rodauth.allocate
      legacy = '1_HMAC_WITH_UNDERSCORES'
      fake_request = Struct.new(:cookies).new({ '_remember' => legacy })
      r.define_singleton_method(:request) { fake_request }

      expect(r.send(:_get_remember_cookie)).to eq(legacy)
    end

    it 'writes an obfuscated id into the cookie on set' do
      r = remember_app.rodauth.allocate
      headers = {}
      r.define_singleton_method(:response) { Struct.new(:headers).new(headers) }
      r.define_singleton_method(:request) { Struct.new(:ssl?).new(false).tap { |s| def s.ssl? = false } }

      r.send(:_set_remember_cookie, 1, 'remkey', Time.now + 1000)
      cookie_header = headers.values.join
      expect(cookie_header).to include(r.obfuscate_account_id(1))
      expect(cookie_header).not_to include('=1_')
    end
  end

  describe 'non-interference with other token consumers' do
    it 'does not override the global split_token / convert_token_id' do
      auth = default_app.rodauth
      # These remain owned by Rodauth's base feature, not our subclass/feature.
      expect(auth.instance_method(:split_token).owner).not_to eq(auth)
      expect(auth.instance_method(:convert_token_id).owner).not_to eq(auth)
    end
  end

  describe 'internal_request composition (Finding #2 regression net)' do
    it 'does not double-obfuscate (or crash) the remember cookie through the internal_request subclass' do
      app = create_roda_app do
        enable :login, :remember, :account_id_obfuscation, :internal_request
        hmac_secret 'h' * 32
        account_id_obfuscation_secret 'a' * 40
        production_env_check false
      end

      # internal_request's own post_configure creates this subclass of the
      # already-configured Auth class and re-runs post_configure on it -- the
      # exact scenario that used to double-install the cookie override.
      internal_class = app.rodauth.const_get(:InternalRequest)
      r = internal_class.allocate
      headers = stub_cookie_write(r)

      expect { r.send(:_set_remember_cookie, 1, 'remkey', Time.now + 1000) }.not_to raise_error

      raw_value = headers.values.join[/_remember=([^;]+)/, 1]
      # Single-obfuscation: the id half is exactly obfuscate_account_id(1). If
      # the old bug were present, the id passed to remember.rb's real
      # _set_remember_cookie would itself be an obfuscated (non-decimal)
      # string, and Integer() on it inside a second round of obfuscation would
      # have raised before we ever got here.
      expect(raw_value).to start_with(r.obfuscate_account_id(1))
    end
  end

  describe 'multi-guard co-enablement (Finding #1 regression net)' do
    before { %w[ACCOUNT_ID_SECRET HMAC_SECRET JWT_SECRET].each { |k| ENV.delete(k) } }
    after { %w[ACCOUNT_ID_SECRET HMAC_SECRET JWT_SECRET].each { |k| ENV.delete(k) } }

    {
      hmac_secret_guard: { env: 'HMAC_SECRET', error: /HMAC_SECRET/ },
      jwt_secret_guard: { env: 'JWT_SECRET', error: /JWT_SECRET/ }
    }.each do |guard, cfg|
      [[guard, :account_id_obfuscation], [:account_id_obfuscation, guard]].each do |order|
        context "with #{guard} + account_id_obfuscation enabled in order #{order.inspect}" do
          it 'still raises the ACCOUNT_ID_SECRET error when the sibling guard secret is present ' \
             'but ACCOUNT_ID_SECRET is not (the collision this feature used to hide behind)' do
            ENV[cfg[:env]] = 'g' * 40

            expect do
              create_roda_app do
                enable(*order)
                production_env_check true
              end
            end.to raise_error(Rodauth::ConfigurationError, /ACCOUNT_ID_SECRET/)
          end

          it "still raises #{guard}'s own error when ACCOUNT_ID_SECRET is present but its secret is not " \
             '(no reverse shadowing)' do
            ENV['ACCOUNT_ID_SECRET'] = 'a' * 40

            expect do
              create_roda_app do
                enable(*order)
                production_env_check true
              end
            end.to raise_error(Rodauth::ConfigurationError, cfg[:error])
          end
        end
      end
    end
  end
end
