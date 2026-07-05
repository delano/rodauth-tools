# spec/rodauth/features/table_guard/table_guard_simple_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'

RSpec.describe 'TableGuard Simple' do
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

  def create_accounts_table(database)
    database.create_table :accounts do
      primary_key :id
      String :email, null: false, unique: true
      String :status_id, default: 'unverified'
    end

    database.create_table :account_password_hashes do
      foreign_key :id, :accounts, primary_key: true
      String :password_hash, null: false
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

  it 'allows feature to be enabled' do
    app = create_roda_app do
      enable :table_guard
    end

    expect(app).not_to be_nil
  end

  it 'raises error in raise mode with missing tables' do
    expect do
      create_roda_app do
        enable :login, :logout
        enable :table_guard
        table_guard_mode :raise
      end
    end.to raise_error(Rodauth::ConfigurationError) do |error|
      expect(error.message).to include('Missing required database tables')
      expect(error.message).to include('accounts')
    end
  end

  it 'succeeds in raise mode when all tables exist' do
    create_accounts_table(db)

    app = create_roda_app do
      enable :login, :logout
      enable :table_guard
      table_guard_mode :raise
    end

    expect(app).not_to be_nil
  end

  it 'logs error but continues in error mode with missing tables' do
    # Capture stderr to verify error was logged
    stderr_output = capture_warnings do
      app = create_roda_app do
        enable :login, :logout
        enable :table_guard
        table_guard_mode :error
      end

      expect(app).not_to be_nil
    end

    expect(stderr_output).to include('CRITICAL: Missing Rodauth tables')
  end

  it 'succeeds in error mode when all tables exist' do
    create_accounts_table(db)

    app = create_roda_app do
      enable :login, :logout
      enable :table_guard
      table_guard_mode :error
    end

    expect(app).not_to be_nil
  end

  it 'does not raise in silent mode' do
    app = create_roda_app do
      enable :login, :logout
      enable :table_guard
      table_guard_mode :silent
    end

    expect(app).not_to be_nil
  end

  it 'warns about missing tables in warn mode' do
    output = capture_warnings do
      create_roda_app do
        enable :login, :logout
        enable :table_guard
        table_guard_mode :warn
      end
    end

    expect(output).to include('Missing required database tables')
    expect(output).to include('accounts')
  end

  it 'allows block handler to continue without error' do
    block_called = false
    received_missing = nil

    app = create_roda_app do
      enable :login
      enable :table_guard
      table_guard_mode do |missing|
        block_called = true
        received_missing = missing
        :continue
      end
    end

    expect(app).not_to be_nil
    expect(block_called).to be true
    expect(received_missing).not_to be_nil
  end

  it 'raises error when block handler returns :error' do
    expect do
      create_roda_app do
        enable :login
        enable :table_guard
        table_guard_mode do |_missing|
          :error
        end
      end
    end.to raise_error(Rodauth::ConfigurationError) do |error|
      expect(error.message).to include('Missing required database tables')
    end
  end

  it 'raises custom message from block handler' do
    custom_message = 'Custom error: Please run migrations!'

    expect do
      create_roda_app do
        enable :login
        enable :table_guard
        table_guard_mode do |_missing|
          custom_message
        end
      end
    end.to raise_error(Rodauth::ConfigurationError, custom_message)
  end

  it 'raises error for invalid mode' do
    expect do
      create_roda_app do
        enable :table_guard
        table_guard_mode :invalid_mode
      end
    end.to raise_error(Rodauth::ConfigurationError) do |error|
      expect(error.message).to include('Invalid table_guard_mode')
    end
  end

  it 'is disabled by default when no mode specified' do
    app = create_roda_app do
      enable :login
      enable :table_guard
      # No mode specified
    end

    expect(app).not_to be_nil
  end

  describe 'sequel generation error handling with a block mode' do
    # Regression: the rescue in handle_sequel_generation used to evaluate
    # table_guard_mode directly, which raises ArgumentError when the user
    # configured a block handler (arity > 0) — masking the real error.

    it 'resolves a block mode to nil instead of invoking it with no args' do
      app = create_roda_app do
        enable :table_guard
        table_guard_mode { |_missing| :continue }
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.send(:table_guard_mode_symbol)).to be_nil
    end

    it 'resolves a symbol mode to its symbol' do
      app = create_roda_app do
        enable :table_guard
        table_guard_mode :silent # avoids raising at boot on the empty test db
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.send(:table_guard_mode_symbol)).to eq(:silent)
    end

    it 'does not crash the error handler when generation fails under a block mode' do
      require 'tempfile'
      tmp = Tempfile.new('table_guard_bad_path')
      # A path whose ancestor is a regular file makes FileUtils.mkdir_p raise,
      # forcing the rescue in handle_sequel_generation to run.
      bad_path = "#{tmp.path}/subdir"

      capture_warnings do
        expect do
          create_roda_app do
            enable :table_guard
            table_guard_mode { |_missing| :continue } # block handler, arity 1
            table_guard_sequel_mode :migration
            table_guard_migration_path bad_path
          end
        end.not_to raise_error # with the bug: ArgumentError (wrong number of arguments)
      end
    ensure
      tmp&.close
      tmp&.unlink
    end
  end

  describe '#table_exists?' do
    # These exercise the db.tables-based existence check (which replaced the
    # SELECT-probe + shared db.loggers mutation).

    it 'returns true for an existing table' do
      create_accounts_table(db)
      app = create_roda_app do
        enable :table_guard
        table_guard_mode :silent
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.table_exists?(:accounts)).to be true
    end

    it 'returns false for a missing table' do
      app = create_roda_app do
        enable :table_guard
        table_guard_mode :silent
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.table_exists?(:does_not_exist)).to be false
    end

    it 'returns true for a skipped table even when it is missing' do
      app = create_roda_app do
        enable :table_guard
        table_guard_mode :silent
        table_guard_skip_tables [:does_not_exist]
      end

      rodauth_instance = app.rodauth.allocate
      expect(rodauth_instance.table_exists?(:does_not_exist)).to be true
    end

    it 'does not mutate db.loggers while checking' do
      require 'logger'
      logger = Logger.new(StringIO.new)
      db.loggers << logger
      app = create_roda_app do
        enable :table_guard
        table_guard_mode :silent
      end

      rodauth_instance = app.rodauth.allocate
      rodauth_instance.table_exists?(:accounts)
      expect(db.loggers).to eq([logger])
    end
  end
end
