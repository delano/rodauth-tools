# spec/rodauth/features/table_guard/table_guard_integration_spec.rb

require "spec_helper"
require "sequel"
require "rodauth"
require "roda"

RSpec.describe "TableGuard Integration" do
  def create_all_tables(db)
    db.create_table :accounts do
      primary_key :id
      String :email, null: false
      String :status_id, default: "unverified"
    end

    db.create_table :account_password_hashes do
      foreign_key :id, :accounts, primary_key: true
      String :password_hash, null: false
    end
  end

  it "raises error during configuration in raise mode" do
    db = Sequel.sqlite

    expect do
      Class.new(Roda) do
        plugin :rodauth do
          self.db db
          enable :login, :logout
          enable :table_guard
          table_guard_mode :raise
        end

        route do |r|
          r.rodauth
        end
      end
    end.to raise_error(Rodauth::ConfigurationError) do |error|
      expect(error.message).to include("Missing required database tables")
      expect(error.message).to include("accounts")
    end
  end

  it "works when all required tables exist" do
    db = Sequel.sqlite
    create_all_tables(db)

    app = Class.new(Roda) do
      plugin :rodauth do
        self.db db
        enable :login, :logout
        enable :table_guard
        table_guard_mode :error
      end

      route do |r|
        r.rodauth
      end
    end

    expect(app).not_to be_nil
  end

  it "does not raise in silent mode" do
    db = Sequel.sqlite

    app = Class.new(Roda) do
      plugin :rodauth do
        self.db db
        enable :login, :logout
        enable :table_guard
        table_guard_mode :silent
      end

      route do |r|
        r.rodauth
      end
    end

    expect(app).not_to be_nil
  end

  it "is disabled by default" do
    db = Sequel.sqlite

    app = Class.new(Roda) do
      plugin :rodauth do
        self.db db
        enable :login
        enable :table_guard
        # No mode set
      end

      route do |r|
        r.rodauth
      end
    end

    expect(app).not_to be_nil
  end
end
