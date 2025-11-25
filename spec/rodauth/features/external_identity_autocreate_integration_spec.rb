# spec/rodauth/features/external_identity_autocreate_integration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'
require 'tempfile'
require 'fileutils'
require 'logger'

RSpec.describe 'Rodauth external_identity :autocreate + table_guard sequel_mode integration' do
  let(:db) { Sequel.sqlite }
  let(:migration_dir) { Dir.mktmpdir }

  after do
    db.disconnect if db
    FileUtils.rm_rf(migration_dir) if migration_dir
  end

  def create_roda_app(&rodauth_block)
    test_db = db

    Class.new(Roda) do
      plugin :rodauth do
        db test_db
        instance_exec(&rodauth_block) if rodauth_block
      end

      route do |r|
        r.rodauth
      end
    end
  end

  # Helper to create accounts table WITHOUT external identity columns
  def create_accounts_table_without_external_columns
    db.create_table :accounts do
      primary_key :id
      String :email, null: false, unique: true
      String :status_id, default: 'unverified'
    end

    db.create_table :account_password_hashes do
      foreign_key :id, :accounts, primary_key: true
      String :password_hash, null: false
    end
  end

  # Helper to check if column exists in table
  def column_exists?(table, column)
    db.schema(table).any? { |col| col[0] == column }
  end

  # Helper to get column schema info
  def column_schema(table, column)
    db.schema(table).find { |col| col[0] == column }
  end

  # Helper to capture STDOUT
  def capture_stdout
    old_stdout = $stdout
    $stdout = StringIO.new
    result = yield
    [result, $stdout.string]
  ensure
    $stdout = old_stdout
  end

  describe ':log mode - generates ALTER TABLE code in output' do
    it 'generates ALTER TABLE statement for missing String column' do
      create_accounts_table_without_external_columns

      _app, output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :log

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      expect(output).to include('Sequel migration code:')
      expect(output).to include('alter_table(:accounts) do')
      expect(output).to include('add_column :stripe_customer_id, String')
      expect(output).to include('end')
    end

    it 'generates ALTER TABLE with correct column type for Integer' do
      create_accounts_table_without_external_columns

      _app, output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :log

          external_identity_check_columns :autocreate
          external_identity_column :redis_id, type: Integer
        end
      end

      expect(output).to include('add_column :redis_id, Integer')
    end

    it 'generates ALTER TABLE with null constraint' do
      create_accounts_table_without_external_columns

      _app, output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :log

          external_identity_check_columns :autocreate
          external_identity_column :required_id, null: false
        end
      end

      expect(output).to include('add_column :required_id, String, null: false')
    end

    it 'generates ALTER TABLE with multiple columns' do
      create_accounts_table_without_external_columns

      _app, output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :log

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
          external_identity_column :github_user_id, type: Integer
          external_identity_column :oauth_token, null: false
        end
      end

      expect(output).to include('alter_table(:accounts) do')
      expect(output).to include('add_column :stripe_customer_id, String')
      expect(output).to include('add_column :github_user_id, Integer')
      expect(output).to include('add_column :oauth_token, String, null: false')
    end

    it 'generates down migration with drop_column statements' do
      create_accounts_table_without_external_columns

      _app, output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :log

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      expect(output).to include('down do')
      expect(output).to include('alter_table(:accounts) do')
      expect(output).to include('drop_column :stripe_customer_id')
    end
  end

  describe ':create mode - actually creates columns in database' do
    it 'creates missing String column in database' do
      create_accounts_table_without_external_columns

      expect(column_exists?(:accounts, :stripe_customer_id)).to be false

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :create

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      expect(column_exists?(:accounts, :stripe_customer_id)).to be true

      # Verify column type
      schema = column_schema(:accounts, :stripe_customer_id)
      expect(schema).not_to be_nil
      expect(schema[1][:type]).to eq(:string)
    end

    it 'creates Integer column with correct type' do
      create_accounts_table_without_external_columns

      expect(column_exists?(:accounts, :github_user_id)).to be false

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :create

          external_identity_check_columns :autocreate
          external_identity_column :github_user_id, type: Integer
        end
      end

      expect(column_exists?(:accounts, :github_user_id)).to be true

      schema = column_schema(:accounts, :github_user_id)
      expect(schema[1][:type]).to eq(:integer)
    end

    it 'creates multiple columns at once' do
      create_accounts_table_without_external_columns

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :create

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
          external_identity_column :github_user_id, type: Integer
          external_identity_column :oauth_token, null: false
        end
      end

      expect(column_exists?(:accounts, :stripe_customer_id)).to be true
      expect(column_exists?(:accounts, :github_user_id)).to be true
      expect(column_exists?(:accounts, :oauth_token)).to be true
    end

    it 'can insert and query data in created columns' do
      create_accounts_table_without_external_columns

      app_class, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :create

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      # Insert data
      db[:accounts].insert(
        email: 'test@example.com',
        stripe_customer_id: 'cus_abc123'
      )

      # Query data
      account = db[:accounts].first
      expect(account[:stripe_customer_id]).to eq('cus_abc123')

      # Verify Rodauth helper method works
      rodauth = app_class.allocate.rodauth
      rodauth.instance_variable_set(:@account, account)
      expect(rodauth.stripe_customer_id).to eq('cus_abc123')
    end
  end

  describe ':migration mode - generates migration file' do
    it 'creates migration file with timestamp' do
      create_accounts_table_without_external_columns

      # Capture migration_dir in local variable
      mig_dir = migration_dir

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :migration
          table_guard_migration_path File.join(mig_dir, 'migrate')

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      # Find generated migration file
      migration_files = Dir.glob(File.join(migration_dir, 'migrate', '*_rodauth_tables.rb'))
      expect(migration_files.length).to eq(1)

      migration_file = migration_files.first
      expect(File.basename(migration_file)).to match(/^\d{14}_.*rodauth.*\.rb$/)
    end

    it 'migration file contains ALTER TABLE statements' do
      create_accounts_table_without_external_columns

      # Capture migration_dir in local variable
      mig_dir = migration_dir

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :migration
          table_guard_migration_path File.join(mig_dir, 'migrate')

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end

      migration_file = Dir.glob(File.join(migration_dir, 'migrate', '*.rb')).first
      migration_content = File.read(migration_file)

      expect(migration_content).to include('Sequel.migration do')
      expect(migration_content).to include('up do')
      expect(migration_content).to include('alter_table(:accounts) do')
      expect(migration_content).to include('add_column :stripe_customer_id, String')
      expect(migration_content).to include('end')
      expect(migration_content).to include('down do')
      expect(migration_content).to include('drop_column :stripe_customer_id')
    end
  end

  describe 'edge cases' do
    it 'external_identity :autocreate without table_guard raises with migration code' do
      create_accounts_table_without_external_columns

      expect do
        create_roda_app do
          enable :external_identity

          external_identity_check_columns :autocreate
          external_identity_column :stripe_customer_id
        end
      end.to raise_error(ArgumentError) do |error|
        expect(error.message).to match(/autocreate/)
        expect(error.message).to match(/Sequel\.migration/)
        expect(error.message).to match(/add_column :stripe_customer_id/)
      end
    end

    it 'works with multiple columns with different constraints' do
      create_accounts_table_without_external_columns

      _app, _output = capture_stdout do
        create_roda_app do
          enable :table_guard
          enable :external_identity

          table_guard_mode :silent
          table_guard_sequel_mode :create

          external_identity_check_columns :autocreate
          external_identity_column :stripe_id
          external_identity_column :github_id, type: Integer, null: false
          external_identity_column :oauth_token, unique: true, index: true
        end
      end

      expect(column_exists?(:accounts, :stripe_id)).to be true
      expect(column_exists?(:accounts, :github_id)).to be true
      expect(column_exists?(:accounts, :oauth_token)).to be true

      # Verify null constraint
      github_schema = column_schema(:accounts, :github_id)
      expect(github_schema[1][:allow_null]).to be false
    end
  end
end
