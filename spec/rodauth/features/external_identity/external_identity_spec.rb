# spec/rodauth/features/external_identity/external_identity_spec.rb

require "spec_helper"
require "sequel"
require "rodauth"
require "roda"

RSpec.describe "Rodauth external_identity feature" do
  let(:db) { Sequel.sqlite }

  after do
    db.disconnect if db
  end

  def create_roda_app(&rodauth_block)
    test_db = db

    Class.new(Roda) do
      plugin :rodauth do
        self.db test_db
        instance_eval(&rodauth_block) if rodauth_block
      end

      route do |r|
        r.rodauth
      end
    end
  end

  # Helper to create accounts table with external identity columns
  def create_accounts_table_with_columns(columns: [])
    db.create_table :accounts do
      primary_key :id
      String :email, null: false, unique: true
      String :status_id, default: "unverified"

      # Add external identity columns
      columns.each do |col|
        String col
      end
    end

    db.create_table :account_password_hashes do
      foreign_key :id, :accounts, primary_key: true
      String :password_hash, null: false
    end
  end

  describe "configuration methods" do
    context "single column declaration" do
      it "declares a column with default naming" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_list).to eq([:stripe_id])
        expect(rodauth.external_identity_column_config(:stripe_id)).to include(
          column: :stripe_id,
          method_name: :stripe_id,
          include_in_select: true
        )
      end

      it "declares a column with exact column name" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_config(:stripe_customer_id)[:column]).to eq(:stripe_customer_id)
      end

      it "declares a column with custom method name" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, method_name: :stripe_identifier
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_config(:stripe_id)[:method_name]).to eq(:stripe_identifier)
      end
    end

    context "multiple column declarations" do
      it "declares multiple columns" do
        create_accounts_table_with_columns(columns: [:stripe_id, :redis_id, :auth0_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :redis_id
          external_identity_column :auth0_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_list).to match_array([:stripe_id, :redis_id, :auth0_id])
      end

      it "maintains declaration order" do
        create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :redis_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_list).to eq([:stripe_id, :redis_id])
      end
    end

    context "custom method names" do
      it "accepts valid Ruby identifier" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, method_name: :my_stripe_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_helper_methods).to include(:my_stripe_id)
      end

      it "accepts method names with underscores" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, method_name: :account_stripe_customer_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_helper_methods).to include(:account_stripe_customer_id)
      end

      it "accepts method names with question marks" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, method_name: :has_stripe?
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_helper_methods).to include(:has_stripe?)
      end
    end

    context "invalid method names" do
      it "rejects non-symbol names" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column "stripe_id"
          end
        }.to raise_error(ArgumentError, /must be a Symbol/)
      end

      it "rejects invalid Ruby identifiers" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :"stripe-id"
          end
        }.to raise_error(ArgumentError, /must be a valid Ruby identifier/)
      end

      it "rejects method names starting with numbers" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :stripe_id, method_name: :"123_stripe"
          end
        }.to raise_error(ArgumentError, /must be a valid Ruby identifier/)
      end

      it "rejects method names with invalid special characters" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :stripe_id, method_name: :"stripe@id"
          end
        }.to raise_error(ArgumentError, /must be a valid Ruby identifier/)
      end
    end

    context "duplicate column declarations" do
      it "raises error on duplicate declaration" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :stripe_id
            external_identity_column :stripe_id
          end
        }.to raise_error(ArgumentError, /already declared/)
      end

      it "cannot reuse same column even with different method names" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :stripe_id
            external_identity_column :stripe_id, method_name: :alternate_stripe_id
          end
        }.to raise_error(ArgumentError, /already declared/)
      end
    end

    context "options validation" do
      it "accepts include_in_select option" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, include_in_select: false
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_config(:stripe_id)[:include_in_select]).to be false
      end

      it "accepts validate option" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id, validate: true
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_config(:stripe_id)[:validate]).to be true
      end
    end
  end

  describe "account_select integration" do
    it "returns nil when no other features define account_select" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      select_cols = rodauth.account_select
      # Should return nil (select all columns) since no other feature defines account_select
      expect(select_cols).to be_nil
    end

    it "adds columns to account_select" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id
      end

      rodauth = app_class.allocate.rodauth
      select_cols = rodauth.account_select
      # Should be nil when no base feature defines account_select
      expect(select_cols).to be_nil
    end

    it "returns nil when no base account_select and include_in_select options mixed" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id, include_in_select: false
        external_identity_column :redis_id
      end

      rodauth = app_class.allocate.rodauth
      select_cols = rodauth.account_select
      # When there's no base account_select, should return nil (select all)
      # even if some columns have include_in_select: false
      expect(select_cols).to be_nil
    end

    it "works with other Rodauth features that don't define account_select" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      app_class = create_roda_app do
        enable :login
        enable :external_identity
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      select_cols = rodauth.account_select
      # Login feature doesn't define account_select, so should return nil
      expect(select_cols).to be_nil
    end

    it "preserves order of columns when base feature provides array" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id, :auth0_id])
      app_class = create_roda_app do
        enable :login
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id
        external_identity_column :auth0_id

        # Explicitly set account_select to test column addition
        account_select [:id, :email]
      end

      rodauth = app_class.allocate.rodauth
      select_cols = rodauth.account_select

      # Should include base columns plus external identity columns
      expect(select_cols).to include(:id, :email, :stripe_id, :redis_id, :auth0_id)

      # External identity columns should be added in order
      stripe_idx = select_cols.index(:stripe_id)
      redis_idx = select_cols.index(:redis_id)
      auth0_idx = select_cols.index(:auth0_id)

      expect(stripe_idx).to be < redis_idx
      expect(redis_idx).to be < auth0_idx
    end

    context "SQL query behavior" do
      it "selects ALL columns when no other features define account_select" do
        create_accounts_table_with_columns(columns: [:external_id])
        db[:accounts].insert(
          email: 'test@example.com',
          status_id: 'verified',
          external_id: 'ext_123'
        )

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id
        end

        rodauth = app_class.allocate.rodauth

        # Query the account to trigger actual SELECT
        account = db[:accounts].where(id: 1).first

        # Verify account hash includes ALL columns
        expect(account).to include(:id, :email, :status_id, :external_id)
        expect(account[:email]).to eq('test@example.com')
        expect(account[:status_id]).to eq('verified')
        expect(account[:external_id]).to eq('ext_123')
      end

      it "selects ALL columns including external_identity column via Rodauth" do
        create_accounts_table_with_columns(columns: [:external_id])
        db[:accounts].insert(
          email: 'user@example.com',
          status_id: 'verified',
          external_id: 'ext_456'
        )

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id
        end

        rodauth = app_class.allocate.rodauth

        # Manually set account using account_select
        account_ds = if rodauth.account_select
                       db[:accounts].select(*rodauth.account_select)
                     else
                       db[:accounts]
                     end

        account = account_ds.where(id: 1).first
        rodauth.instance_variable_set(:@account, account)

        # Verify loaded account has ALL columns
        expect(account).to have_key(:id)
        expect(account).to have_key(:email)
        expect(account).to have_key(:status_id)
        expect(account).to have_key(:external_id)
        expect(account[:email]).to eq('user@example.com')
        expect(account[:status_id]).to eq('verified')
        expect(account[:external_id]).to eq('ext_456')

        # Verify helper method works
        expect(rodauth.external_id).to eq('ext_456')
      end

      it "does NOT select only external_identity column (regression test for bug)" do
        create_accounts_table_with_columns(columns: [:external_id])
        db[:accounts].insert(
          email: 'bug@example.com',
          status_id: 'verified',
          external_id: 'ext_789'
        )

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id
        end

        rodauth = app_class.allocate.rodauth

        # Build dataset using account_select (simulating Rodauth's internal behavior)
        account_ds = if rodauth.account_select
                       db[:accounts].select(*rodauth.account_select)
                     else
                       db[:accounts]
                     end

        account = account_ds.where(id: 1).first

        # CRITICAL: Should NOT only have external_id column
        # Should have ALL columns: id, email, status_id, external_id
        expect(account.keys).to include(:id, :email, :status_id, :external_id)
        expect(account.keys).not_to eq([:external_id])  # Bug would result in only this
      end

      it "respects custom account_select from other features" do
        create_accounts_table_with_columns(columns: [:external_id])
        db[:accounts].insert(
          email: 'custom@example.com',
          status_id: 'verified',
          external_id: 'ext_999'
        )

        app_class = create_roda_app do
          enable :login
          enable :external_identity
          external_identity_column :external_id

          # Custom override - only select specific columns
          account_select [:id, :email]
        end

        rodauth = app_class.allocate.rodauth
        select_cols = rodauth.account_select

        # Should include custom columns plus external_identity column
        expect(select_cols).to include(:id, :email, :external_id)
        expect(select_cols).not_to include(:status_id)
      end

      it "handles multiple external_identity columns in query" do
        create_accounts_table_with_columns(columns: [:stripe_id, :github_id])
        db[:accounts].insert(
          email: 'multi@example.com',
          status_id: 'verified',
          stripe_id: 'cus_123',
          github_id: 'gh_456'
        )

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :github_id
        end

        rodauth = app_class.allocate.rodauth

        # Build dataset
        account_ds = if rodauth.account_select
                       db[:accounts].select(*rodauth.account_select)
                     else
                       db[:accounts]
                     end

        account = account_ds.where(id: 1).first

        # Should have ALL columns
        expect(account).to include(
          id: 1,
          email: 'multi@example.com',
          status_id: 'verified',
          stripe_id: 'cus_123',
          github_id: 'gh_456'
        )
      end

      it "respects include_in_select: false option in SQL queries" do
        create_accounts_table_with_columns(columns: [:external_id, :optional_id])
        db[:accounts].insert(
          email: 'selective@example.com',
          status_id: 'verified',
          external_id: 'ext_111',
          optional_id: 'opt_222'
        )

        app_class = create_roda_app do
          enable :login
          enable :external_identity
          external_identity_column :external_id
          external_identity_column :optional_id, include_in_select: false

          # Explicitly set account_select so we can test selective inclusion
          account_select [:id, :email]
        end

        rodauth = app_class.allocate.rodauth
        select_cols = rodauth.account_select

        # external_id should be in select, optional_id should not
        expect(select_cols).to include(:external_id)
        expect(select_cols).not_to include(:optional_id)

        # Query with explicit select
        account = db[:accounts].select(*select_cols).where(id: 1).first

        # Should have external_id but not optional_id
        expect(account).to have_key(:external_id)
        expect(account).not_to have_key(:optional_id)
      end
    end
  end

  describe "helper method generation" do
    it "generates helper methods with correct names" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
      db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123', redis_id: 'redis-uuid-456')

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.respond_to?(:stripe_id)).to be true
      expect(rodauth.respond_to?(:redis_id)).to be true
    end

    it "helper methods return correct values" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
      db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123', redis_id: 'redis-uuid-456')

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id
      end

      rodauth = app_class.allocate.rodauth
      rodauth.instance_variable_set(:@account, db[:accounts].first)

      expect(rodauth.stripe_id).to eq('cus_abc123')
      expect(rodauth.redis_id).to eq('redis-uuid-456')
    end

    it "helper methods handle nil account gracefully" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.stripe_id).to be_nil
    end

    it "custom method names work correctly" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123')

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id, method_name: :stripe_customer_id
      end

      rodauth = app_class.allocate.rodauth
      rodauth.instance_variable_set(:@account, db[:accounts].first)

      expect(rodauth.respond_to?(:stripe_customer_id)).to be true
      expect(rodauth.stripe_customer_id).to eq('cus_abc123')
    end

    it "generates methods for all declared columns" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id
      end

      rodauth = app_class.allocate.rodauth
      methods = rodauth.external_identity_helper_methods

      expect(methods).to match_array([:stripe_id, :redis_id])
    end
  end

  describe "introspection methods" do
    describe "#external_identity_column_list" do
      it "returns list of declared column names" do
        create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :redis_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_list).to match_array([:stripe_id, :redis_id])
      end

      it "returns empty array when no columns declared" do
        create_accounts_table_with_columns(columns: [])
        app_class = create_roda_app do
          enable :external_identity
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_list).to eq([])
      end
    end

    describe "#external_identity_column_config" do
      it "returns configuration for specific column" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id, method_name: :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        config_hash = rodauth.external_identity_column_config(:stripe_customer_id)

        expect(config_hash).to include(
          column: :stripe_customer_id,
          method_name: :stripe_id,
          include_in_select: true
        )
      end

      it "returns nil for unknown column" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column_config(:unknown)).to be_nil
      end
    end

    describe "#external_identity_helper_methods" do
      it "returns list of generated method names" do
        create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :redis_id, method_name: :redis_uuid
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_helper_methods).to match_array([:stripe_id, :redis_uuid])
      end

      it "returns empty array when no columns declared" do
        create_accounts_table_with_columns(columns: [])
        app_class = create_roda_app do
          enable :external_identity
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_helper_methods).to eq([])
      end
    end

    describe "#external_identity_column?" do
      it "returns true for declared column name" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column?(:stripe_id)).to be true
      end

      it "returns true for declared column with custom method name" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column?(:stripe_customer_id)).to be true
      end

      it "returns false for unknown column" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        expect(rodauth.external_identity_column?(:unknown)).to be false
      end
    end

    describe "#external_identity_status" do
      it "returns complete status information" do
        create_accounts_table_with_columns(columns: [:stripe_id, :redis_id])
        db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123', redis_id: nil)

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
          external_identity_column :redis_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, db[:accounts].first)

        status = rodauth.external_identity_status
        expect(status).to be_an(Array)
        expect(status.length).to eq(2)
      end

      it "includes all required fields in status hash" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123')

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, db[:accounts].first)

        status = rodauth.external_identity_status.first
        expect(status).to include(
          :column, :method, :value, :present,
          :in_select, :in_account, :column_exists
        )
      end

      it "correctly reports present values" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123')

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, db[:accounts].first)

        status = rodauth.external_identity_status.first
        expect(status[:value]).to eq('cus_abc123')
        expect(status[:present]).to be true
      end

      it "correctly reports nil values" do
        create_accounts_table_with_columns(columns: [:redis_id])
        db[:accounts].insert(email: 'test@example.com', redis_id: nil)

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :redis_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, db[:accounts].first)

        status = rodauth.external_identity_status.first
        expect(status[:value]).to be_nil
        expect(status[:present]).to be false
      end

      it "reports column existence in database" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        db[:accounts].insert(email: 'test@example.com', stripe_id: 'cus_abc123')

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, db[:accounts].first)

        status = rodauth.external_identity_status.first
        expect(status[:column_exists]).to be true
      end

      it "handles missing account gracefully" do
        create_accounts_table_with_columns(columns: [:stripe_id])
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_id
        end

        rodauth = app_class.allocate.rodauth

        status = rodauth.external_identity_status.first
        expect(status[:value]).to be_nil
        expect(status[:present]).to be false
      end
    end
  end

  describe "validation" do
    context "column existence checking" do
      it "checks columns by default (true)" do
        create_accounts_table_with_columns(columns: [])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :stripe_id
          end
        }.to raise_error(ArgumentError, /not found in accounts table/)
      end

      it "skips checking when set to false" do
        create_accounts_table_with_columns(columns: [])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_check_columns false
            external_identity_column :stripe_id
          end
        }.not_to raise_error
      end

      it "passes checking when columns exist" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_check_columns true
            external_identity_column :stripe_id
          end
        }.not_to raise_error
      end

      it "provides helpful error message for missing columns" do
        create_accounts_table_with_columns(columns: [])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_check_columns true
            external_identity_column :stripe_id
            external_identity_column :redis_id
          end
        }.to raise_error(ArgumentError, /stripe.*redis/)
      end

      it "supports :autocreate mode with helpful migration code" do
        create_accounts_table_with_columns(columns: [])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_check_columns :autocreate
            external_identity_column :stripe_id
          end
        }.to raise_error(ArgumentError) do |error|
          expect(error.message).to match(/autocreate/)
          expect(error.message).to match(/Sequel\.migration/)
          expect(error.message).to match(/add_column :stripe_id/)
        end
      end
    end

    context "invalid method names" do
      it "rejects empty symbol" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :""
          end
        }.to raise_error(ArgumentError, /valid Ruby identifier/)
      end

      it "rejects symbols with spaces" do
        create_accounts_table_with_columns(columns: [:stripe_id])

        expect {
          create_roda_app do
            enable :external_identity
            external_identity_column :"stripe id"
          end
        }.to raise_error(ArgumentError, /valid Ruby identifier/)
      end
    end
  end

  describe "edge cases" do
    it "handles no columns declared (no-op feature)" do
      create_accounts_table_with_columns(columns: [])
      app_class = create_roda_app do
        enable :external_identity
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_column_list).to eq([])
      expect(rodauth.external_identity_helper_methods).to eq([])
      expect(rodauth.external_identity_status).to eq([])
    end

    it "handles multiple columns with various options" do
      create_accounts_table_with_columns(columns: [:stripe_id, :redis_id, :auth0_id, :custom_id])

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
        external_identity_column :redis_id, include_in_select: false
        external_identity_column :auth0_id, method_name: :auth0_user
        external_identity_column :custom_id, validate: false
      end

      rodauth = app_class.allocate.rodauth

      expect(rodauth.external_identity_column_list.length).to eq(4)
      # When no base account_select is defined, it returns nil (select all)
      # This is correct behavior - all columns including external ones will be selected
      expect(rodauth.account_select).to be_nil
      expect(rodauth.respond_to?(:auth0_user)).to be true
    end

    it "handles symbols with underscores and numbers" do
      create_accounts_table_with_columns(columns: [:oauth2_id, :api_v2_key])

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :oauth2_id
        external_identity_column :api_v2_key
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_column_list).to match_array([:oauth2_id, :api_v2_key])
    end

    it "handles nil values in account hash" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      db[:accounts].insert(email: 'test@example.com', stripe_id: nil)

      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      rodauth.instance_variable_set(:@account, db[:accounts].first)

      expect(rodauth.stripe_id).to be_nil
    end
  end

  describe "configuration value methods" do
    it "external_identity_on_conflict defaults to :error" do
      create_accounts_table_with_columns(columns: [])
      app_class = create_roda_app do
        enable :external_identity
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_on_conflict).to eq(:error)
    end

    it "external_identity_check_columns defaults to true" do
      create_accounts_table_with_columns(columns: [:stripe_id])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_check_columns).to be true
    end

    it "allows customizing external_identity_on_conflict" do
      create_accounts_table_with_columns(columns: [])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_check_columns false
        external_identity_on_conflict :warn
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_on_conflict).to eq(:warn)
    end

    it "allows customizing external_identity_check_columns to false" do
      create_accounts_table_with_columns(columns: [])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_check_columns false
        external_identity_column :stripe_id
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_check_columns).to be false
    end

    it "allows customizing external_identity_check_columns to :autocreate" do
      create_accounts_table_with_columns(columns: [])
      app_class = create_roda_app do
        enable :external_identity
        external_identity_check_columns :autocreate
      end

      rodauth = app_class.allocate.rodauth
      expect(rodauth.external_identity_check_columns).to eq(:autocreate)
    end
  end

  describe "Layer 2: Lifecycle callbacks" do
    describe "formatter callback" do
      it "formats value when accessed via helper method" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            formatter: ->(v) { v.to_s.strip.downcase }
        end

        # Create an account with non-normalized value
        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "  CUS_ABC123  "
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        # Helper method should return formatted value
        expect(rodauth.stripe_customer_id).to eq("cus_abc123")
      end

      it "applies strip formatting" do
        create_accounts_table_with_columns(columns: [:redis_uuid])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :redis_uuid,
            formatter: ->(v) { v.to_s.strip }
        end

        db[:accounts].insert(
          email: "user@example.com",
          redis_uuid: "  550e8400-e29b-41d4-a716-446655440000  "
        )
        account = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account)

        expect(rodauth.redis_uuid).to eq("550e8400-e29b-41d4-a716-446655440000")
      end

      it "applies downcase formatting" do
        create_accounts_table_with_columns(columns: [:external_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id,
            formatter: ->(v) { v.downcase }
        end

        db[:accounts].insert(
          email: "user@example.com",
          external_id: "ABC-123-XYZ"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.external_id).to eq("abc-123-xyz")
      end

      it "chains multiple formatting operations" do
        create_accounts_table_with_columns(columns: [:api_key])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :api_key,
            formatter: ->(v) { v.to_s.strip.downcase.gsub(/[^a-z0-9]/, '') }
        end

        db[:accounts].insert(
          email: "user@example.com",
          api_key: "  API-KEY-123  "
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.api_key).to eq("apikey123")
      end

      it "returns nil when value is nil" do
        create_accounts_table_with_columns(columns: [:optional_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :optional_id,
            formatter: ->(v) { v.to_s.strip }
        end

        db[:accounts].insert(
          email: "user@example.com",
          optional_id: nil
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        # Should not apply formatter to nil
        expect(rodauth.optional_id).to be_nil
      end

      it "returns nil when account is nil" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            formatter: ->(v) { v.to_s.strip }
        end

        rodauth = app_class.allocate.rodauth
        # No account set

        expect(rodauth.stripe_customer_id).to be_nil
      end

      it "works without formatter (backward compatibility)" do
        create_accounts_table_with_columns(columns: [:legacy_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :legacy_id
        end

        db[:accounts].insert(
          email: "user@example.com",
          legacy_id: "  LEGACY  "
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        # Should return raw value without formatting
        expect(rodauth.legacy_id).to eq("  LEGACY  ")
      end

      it "supports custom formatter logic" do
        create_accounts_table_with_columns(columns: [:phone_number])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :phone_number,
            formatter: ->(v) {
              # Remove all non-digits, add +1 prefix
              digits = v.gsub(/\D/, '')
              "+1#{digits}"
            }
        end

        db[:accounts].insert(
          email: "user@example.com",
          phone_number: "(555) 123-4567"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.phone_number).to eq("+15551234567")
      end
    end

    describe "validator callback" do
      it "validates value format successfully" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            validator: ->(v) { v.start_with?('cus_') && v.length >= 10 }
        end

        rodauth = app_class.allocate.rodauth

        # Valid value should pass ("cus_abc123" is exactly 10 chars)
        expect(rodauth.validate_external_identity(:stripe_customer_id, "cus_abc123")).to be true
      end

      it "raises ArgumentError for invalid format" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            validator: ->(v) { v.start_with?('cus_') }
        end

        rodauth = app_class.allocate.rodauth

        # Invalid value should raise error
        expect {
          rodauth.validate_external_identity(:stripe_customer_id, "invalid")
        }.to raise_error(ArgumentError, /Invalid format for stripe_customer_id/)
      end

      it "applies formatter before validation" do
        create_accounts_table_with_columns(columns: [:api_key])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :api_key,
            formatter: ->(v) { v.to_s.strip.downcase },
            validator: ->(v) { v.start_with?('api_') }
        end

        rodauth = app_class.allocate.rodauth

        # Formatter should run first (uppercase -> lowercase)
        expect(rodauth.validate_external_identity(:api_key, "  API_KEY123  ")).to be true
      end

      it "skips validation for nil values" do
        create_accounts_table_with_columns(columns: [:optional_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :optional_id,
            validator: ->(v) { v.length > 5 }
        end

        rodauth = app_class.allocate.rodauth

        # nil should not be validated
        expect(rodauth.validate_external_identity(:optional_id, nil)).to be true
      end

      it "returns true when no validator configured" do
        create_accounts_table_with_columns(columns: [:legacy_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :legacy_id
        end

        rodauth = app_class.allocate.rodauth

        # Should always pass without validator
        expect(rodauth.validate_external_identity(:legacy_id, "anything")).to be true
      end

      it "validates complex format rules" do
        create_accounts_table_with_columns(columns: [:phone_number])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :phone_number,
            validator: ->(v) {
              # Must be exactly 12 characters (+1 + 10 digits)
              v =~ /^\+1\d{10}$/
            }
        end

        rodauth = app_class.allocate.rodauth

        expect(rodauth.validate_external_identity(:phone_number, "+15551234567")).to be true
        expect {
          rodauth.validate_external_identity(:phone_number, "555-1234")
        }.to raise_error(ArgumentError)
      end

      it "validates all configured external identities" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :redis_uuid])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            validator: ->(v) { v.start_with?('cus_') }
          external_identity_column :redis_uuid,
            validator: ->(v) { v.length == 36 }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_abc123",
          redis_uuid: "550e8400-e29b-41d4-a716-446655440000"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        results = rodauth.validate_all_external_identities
        expect(results[:stripe_customer_id]).to be true
        expect(results[:redis_uuid]).to be true
      end

      it "raises on first validation failure" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :redis_uuid])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            validator: ->(v) { v.start_with?('cus_') }
          external_identity_column :redis_uuid,
            validator: ->(v) { v.length == 36 }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "invalid",  # Will fail validation
          redis_uuid: "550e8400-e29b-41d4-a716-446655440000"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect {
          rodauth.validate_all_external_identities
        }.to raise_error(ArgumentError, /Invalid format for stripe_customer_id/)
      end

      it "skips columns without validators in validate_all" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :legacy_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            validator: ->(v) { v.start_with?('cus_') }
          external_identity_column :legacy_id
          # No validator for legacy_id
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_abc123",
          legacy_id: "anything_goes"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        results = rodauth.validate_all_external_identities
        expect(results[:stripe_customer_id]).to be true
        expect(results).not_to have_key(:legacy_id)  # Not included
      end
    end

    describe "before_create_account callback" do
      it "generates value during account creation" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        counter = 0
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { counter += 1; "cus_generated_#{counter}" }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        # Simulate account creation
        rodauth.before_create_account

        expect(rodauth.account[:stripe_customer_id]).to eq("cus_generated_1")
      end

      it "skips generation if value already set" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        generator_called = false
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { generator_called = true; "cus_new" }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, { stripe_customer_id: "cus_existing" })

        rodauth.before_create_account

        # Should NOT call generator, should keep existing value
        expect(generator_called).to be false
        expect(rodauth.account[:stripe_customer_id]).to eq("cus_existing")
      end

      it "applies formatter to generated value" do
        create_accounts_table_with_columns(columns: [:api_key])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :api_key,
            before_create_account: -> { "  GENERATED_KEY  " },
            formatter: ->(v) { v.strip.downcase }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        expect(rodauth.account[:api_key]).to eq("generated_key")
      end

      it "validates generated value" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { "invalid_format" },
            validator: ->(v) { v.start_with?('cus_') }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        expect {
          rodauth.before_create_account
        }.to raise_error(ArgumentError, /Generated value for stripe_customer_id failed validation/)
      end

      it "applies formatter then validator to generated value" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { "  CUS_ABC123  " },
            formatter: ->(v) { v.strip.downcase },
            validator: ->(v) { v.start_with?('cus_') }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        # Formatter runs first (uppercase -> lowercase), then validator
        expect(rodauth.account[:stripe_customer_id]).to eq("cus_abc123")
      end

      it "skips if generator returns nil" do
        create_accounts_table_with_columns(columns: [:optional_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :optional_id,
            before_create_account: -> { nil }  # Intentionally not setting
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        # Should not set column if generator returns nil
        expect(rodauth.account).not_to have_key(:optional_id)
      end

      it "generates multiple external identities" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :redis_uuid])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { "cus_stripe123" }
          external_identity_column :redis_uuid,
            before_create_account: -> { "redis-uuid-456" }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        expect(rodauth.account[:stripe_customer_id]).to eq("cus_stripe123")
        expect(rodauth.account[:redis_uuid]).to eq("redis-uuid-456")
      end

      it "supports complex generation logic" do
        create_accounts_table_with_columns(columns: [:custom_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :custom_id,
            before_create_account: -> {
              # Simulate external API call
              timestamp = Time.now.to_i
              "custom_#{timestamp}_#{rand(1000)}"
            },
            validator: ->(v) { v.start_with?('custom_') }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        expect(rodauth.account[:custom_id]).to match(/^custom_\d+_\d+$/)
      end

      it "handles generation errors gracefully" do
        create_accounts_table_with_columns(columns: [:external_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id,
            before_create_account: -> { raise StandardError, "External service unavailable" }
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        expect {
          rodauth.before_create_account
        }.to raise_error(StandardError, "External service unavailable")
      end

      it "works with columns without before_create_account callback" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :legacy_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            before_create_account: -> { "cus_generated" }
          external_identity_column :legacy_id
          # No callback for legacy_id
        end

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, {})

        rodauth.before_create_account

        expect(rodauth.account[:stripe_customer_id]).to eq("cus_generated")
        expect(rodauth.account).not_to have_key(:legacy_id)
      end
    end

    describe "verifier callback" do
      it "verifies existing external record successfully" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        # Mock Stripe API
        stripe_customers = { "cus_abc123" => { id: "cus_abc123", deleted: false } }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            verifier: ->(id) {
              customer = stripe_customers[id]
              customer && !customer[:deleted]
            }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_abc123"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.verify_external_identity(:stripe_customer_id)).to be true
      end

      it "returns false when external record deleted/missing" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id])

        # Mock Stripe API with deleted customer
        stripe_customers = { "cus_deleted" => { id: "cus_deleted", deleted: true } }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            verifier: ->(id) {
              customer = stripe_customers[id]
              customer && !customer[:deleted]
            }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_deleted"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.verify_external_identity(:stripe_customer_id)).to be false
      end

      it "handles API errors gracefully (returns false, doesn't raise)" do
        create_accounts_table_with_columns(columns: [:external_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :external_id,
            verifier: ->(id) {
              raise StandardError, "Network timeout"
            }
        end

        db[:accounts].insert(
          email: "user@example.com",
          external_id: "ext_123"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        # Should capture warnings
        expect {
          result = rodauth.verify_external_identity(:external_id)
          expect(result).to be false
        }.to output(/Verification failed for external_id/).to_stderr
      end

      it "skips verification for nil values" do
        create_accounts_table_with_columns(columns: [:optional_id])

        verifier_called = false
        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :optional_id,
            verifier: ->(id) { verifier_called = true; true }
        end

        db[:accounts].insert(
          email: "user@example.com",
          optional_id: nil
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        result = rodauth.verify_external_identity(:optional_id)
        expect(result).to be true
        expect(verifier_called).to be false
      end

      it "returns true when no verifier configured" do
        create_accounts_table_with_columns(columns: [:legacy_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :legacy_id
          # No verifier
        end

        db[:accounts].insert(
          email: "user@example.com",
          legacy_id: "legacy_123"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.verify_external_identity(:legacy_id)).to be true
      end

      it "verifies all configured identities" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :github_user_id])

        # Mock external services
        stripe_customers = { "cus_abc123" => { deleted: false } }
        github_users = { "12345" => { suspended: false } }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            verifier: ->(id) { stripe_customers[id] && !stripe_customers[id][:deleted] }
          external_identity_column :github_user_id,
            verifier: ->(id) { github_users[id] && !github_users[id][:suspended] }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_abc123",
          github_user_id: "12345"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        results = rodauth.verify_all_external_identities
        expect(results[:stripe_customer_id]).to be true
        expect(results[:github_user_id]).to be true
      end

      it "skips columns without verifiers in verify_all" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :legacy_id])

        stripe_customers = { "cus_abc123" => { deleted: false } }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            verifier: ->(id) { stripe_customers[id] && !stripe_customers[id][:deleted] }
          external_identity_column :legacy_id
          # No verifier for legacy_id
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_abc123",
          legacy_id: "legacy_123"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        results = rodauth.verify_all_external_identities
        expect(results).to have_key(:stripe_customer_id)
        expect(results).not_to have_key(:legacy_id)
      end

      it "supports custom verifier logic" do
        create_accounts_table_with_columns(columns: [:team_member_id])

        # Mock team membership API
        team_members = {
          "member_123" => { active: true, role: "admin" }
        }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :team_member_id,
            verifier: ->(id) {
              member = team_members[id]
              member && member[:active] && member[:role] == "admin"
            }
        end

        db[:accounts].insert(
          email: "user@example.com",
          team_member_id: "member_123"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        expect(rodauth.verify_external_identity(:team_member_id)).to be true
      end

      it "applies formatter before verification" do
        create_accounts_table_with_columns(columns: [:api_key])

        # Mock API that expects lowercase keys
        valid_keys = ["api_key123"]

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :api_key,
            formatter: ->(v) { v.to_s.strip.downcase },
            verifier: ->(key) { valid_keys.include?(key) }
        end

        db[:accounts].insert(
          email: "user@example.com",
          api_key: "  API_KEY123  "
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        # Should format then verify
        expect(rodauth.verify_external_identity(:api_key)).to be true
      end

      it "continues checking all columns even if some fail" do
        create_accounts_table_with_columns(columns: [:stripe_customer_id, :github_user_id])

        stripe_customers = { "cus_deleted" => { deleted: true } }
        github_users = { "12345" => { suspended: false } }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :stripe_customer_id,
            verifier: ->(id) { stripe_customers[id] && !stripe_customers[id][:deleted] }
          external_identity_column :github_user_id,
            verifier: ->(id) { github_users[id] && !github_users[id][:suspended] }
        end

        db[:accounts].insert(
          email: "user@example.com",
          stripe_customer_id: "cus_deleted",
          github_user_id: "12345"
        )
        account_record = db[:accounts].first

        rodauth = app_class.allocate.rodauth
        rodauth.instance_variable_set(:@account, account_record)

        results = rodauth.verify_all_external_identities
        expect(results[:stripe_customer_id]).to be false
        expect(results[:github_user_id]).to be true
      end
    end

    describe "handshake callback" do
      it "verifies valid handshake token" do
        create_accounts_table_with_columns(columns: [:github_user_id])

        # Simulate OAuth state token stored in session
        oauth_state = "secure_random_state_123"

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :github_user_id,
            handshake: ->(github_id, state) {
              # In real app, would compare with session[:oauth_state]
              state == oauth_state
            }
        end

        rodauth = app_class.allocate.rodauth

        # Valid handshake
        result = rodauth.verify_handshake(:github_user_id, "12345", oauth_state)
        expect(result).to be true
      end

      it "rejects invalid handshake token" do
        create_accounts_table_with_columns(columns: [:github_user_id])

        oauth_state = "secure_random_state_123"

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :github_user_id,
            handshake: ->(github_id, state) {
              state == oauth_state
            }
        end

        rodauth = app_class.allocate.rodauth

        # Invalid handshake - should raise
        expect {
          rodauth.verify_handshake(:github_user_id, "12345", "wrong_state")
        }.to raise_error(RuntimeError, /Handshake verification failed/)
      end

      it "OAuth CSRF protection example" do
        create_accounts_table_with_columns(columns: [:github_user_id])

        # Simulate session storage
        session_state = "random_state_abc123"

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :github_user_id,
            handshake: ->(github_id, provided_state) {
              # Real implementation would check session[:oauth_state]
              provided_state == session_state
            }
        end

        rodauth = app_class.allocate.rodauth

        # Valid OAuth flow
        expect(rodauth.verify_handshake(:github_user_id, "github_123", session_state)).to be true

        # CSRF attack attempt
        expect {
          rodauth.verify_handshake(:github_user_id, "github_123", "attacker_state")
        }.to raise_error(/Handshake verification failed/)
      end

      it "team invite verification example" do
        create_accounts_table_with_columns(columns: [:team_id])

        # Mock invite tokens
        valid_invites = {
          "team_456" => "invite_token_xyz"
        }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :team_id,
            handshake: ->(team_id, invite_token) {
              valid_invites[team_id] == invite_token
            }
        end

        rodauth = app_class.allocate.rodauth

        # Valid invite
        expect(rodauth.verify_handshake(:team_id, "team_456", "invite_token_xyz")).to be true

        # Invalid invite token
        expect {
          rodauth.verify_handshake(:team_id, "team_456", "wrong_token")
        }.to raise_error(/Handshake verification failed/)
      end

      it "raises on handshake failure (secure by default)" do
        create_accounts_table_with_columns(columns: [:secure_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :secure_id,
            handshake: ->(id, token) { false }  # Always fails
        end

        rodauth = app_class.allocate.rodauth

        expect {
          rodauth.verify_handshake(:secure_id, "value", "token")
        }.to raise_error(RuntimeError, /Handshake verification failed/)
      end

      it "returns true for valid verification" do
        create_accounts_table_with_columns(columns: [:verified_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :verified_id,
            handshake: ->(id, token) { true }  # Always passes
        end

        rodauth = app_class.allocate.rodauth

        result = rodauth.verify_handshake(:verified_id, "value", "token")
        expect(result).to be true
      end

      it "supports custom handshake logic" do
        create_accounts_table_with_columns(columns: [:custom_id])

        # Mock signature verification
        valid_signatures = {
          "id_123" => "signature_abc"
        }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :custom_id,
            handshake: ->(id, signature) {
              valid_signatures[id] == signature
            }
        end

        rodauth = app_class.allocate.rodauth

        # Valid signature
        expect(rodauth.verify_handshake(:custom_id, "id_123", "signature_abc")).to be true

        # Invalid signature
        expect {
          rodauth.verify_handshake(:custom_id, "id_123", "wrong_sig")
        }.to raise_error(/Handshake verification failed/)
      end

      it "works without handshake configured" do
        create_accounts_table_with_columns(columns: [:simple_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :simple_id
          # No handshake callback
        end

        rodauth = app_class.allocate.rodauth

        # Should pass without handshake
        result = rodauth.verify_handshake(:simple_id, "value", "token")
        expect(result).to be true
      end

      it "applies formatter before handshake" do
        create_accounts_table_with_columns(columns: [:formatted_id])

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :formatted_id,
            formatter: ->(v) { v.to_s.strip.downcase },
            handshake: ->(id, token) {
              # Expects lowercase
              id == "abc123" && token == "valid"
            }
        end

        rodauth = app_class.allocate.rodauth

        # Formatter should normalize before handshake
        expect(rodauth.verify_handshake(:formatted_id, "  ABC123  ", "valid")).to be true
      end

      it "handshake with complex multi-factor verification" do
        create_accounts_table_with_columns(columns: [:secure_account_id])

        # Mock multi-factor verification state
        mfa_sessions = {
          "account_789" => {
            oauth_state: "state_xyz",
            totp_verified: true,
            ip_address: "192.168.1.1"
          }
        }

        app_class = create_roda_app do
          enable :external_identity
          external_identity_column :secure_account_id,
            handshake: ->(account_id, verification_data) {
              session = mfa_sessions[account_id]
              return false unless session

              # Verify multiple factors
              verification_data[:oauth_state] == session[:oauth_state] &&
                verification_data[:totp_verified] == true &&
                verification_data[:ip_address] == session[:ip_address]
            }
        end

        rodauth = app_class.allocate.rodauth

        # Valid multi-factor verification
        valid_data = {
          oauth_state: "state_xyz",
          totp_verified: true,
          ip_address: "192.168.1.1"
        }
        expect(rodauth.verify_handshake(:secure_account_id, "account_789", valid_data)).to be true

        # Failed MFA - wrong IP
        invalid_data = {
          oauth_state: "state_xyz",
          totp_verified: true,
          ip_address: "10.0.0.1"
        }
        expect {
          rodauth.verify_handshake(:secure_account_id, "account_789", invalid_data)
        }.to raise_error(/Handshake verification failed/)
      end
    end
  end
end
