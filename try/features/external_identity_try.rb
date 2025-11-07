# try/features/external_identity_try.rb
#
# frozen_string_literal: true

# Tryouts v3 tests for external_identity Rodauth feature
#
# Run with:
#   bundle exec try --agent try/features/external_identity_try.rb
#   bundle exec try --verbose try/features/external_identity_try.rb

require 'sequel'
require 'roda'
require 'rodauth'
require_relative '../../lib/rodauth/features/external_identity'

DB = Sequel.sqlite

# Create accounts table with common external identity columns
DB.create_table :accounts do
  primary_key :id
  String :email, null: false, unique: true
  String :status_id, default: "unverified"
  String :stripe_id
  String :stripe_customer_id
  String :redis_id
  String :auth0_id
  String :oauth2_id
  String :api_v2_key
  String :custom_id
end

DB.create_table :account_password_hashes do
  foreign_key :id, :accounts, primary_key: true
  String :password_hash, null: false
end

## Feature can be enabled
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
  end

  route do |r|
    r.rodauth
  end
end

@app_class < Roda
#=> true

## Single column with default naming
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_list
#=> [:stripe_id]

## Column config includes correct defaults
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:column]
#=> :stripe_id

## Method name uses correct default
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:method_name]
#=> :stripe_id

## include_in_select defaults to true
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:include_in_select]
#=> true

## Explicit column name
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_customer_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_customer_id)[:column]
#=> :stripe_customer_id

## Custom method name
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, method_name: :stripe_identifier
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:method_name]
#=> :stripe_identifier

## Multiple column declarations
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
    external_identity_column :auth0_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_list
#=> [:stripe_id, :redis_id, :auth0_id]

## Valid method name with underscores
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, method_name: :account_stripe_customer_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_helper_methods.first
#=> :account_stripe_customer_id

## Valid method name with question mark
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, method_name: :has_stripe?
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_helper_methods.first
#=> :has_stripe?

## Invalid name (non-symbol) raises error
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column "stripe_id"
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("must be a Symbol")
end
#=> true

## Invalid identifier with dash raises error
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column :"stripe-id"
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("valid Ruby identifier")
end
#=> true

## Method name starting with number raises error
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column :stripe_id, method_name: :"123_stripe"
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("valid Ruby identifier")
end
#=> true

## Duplicate declaration raises error
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column :stripe_id
      external_identity_column :stripe_id
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("already declared")
end
#=> true

## Cannot reuse same column even with different method names
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column :stripe_id
      external_identity_column :stripe_id, method_name: :alternate_stripe_id
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("already declared")
end
#=> true

## include_in_select option false
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, include_in_select: false
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:include_in_select]
#=> false

## validate option true
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, validate: true
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:stripe_id)[:validate]
#=> true

## Columns added to account_select
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@select_cols = @rodauth.account_select
@select_cols.include?(:stripe_id) && @select_cols.include?(:redis_id)
#=> true

## No duplicates in account_select
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.account_select.count(:stripe_id)
#=> 1

## include_in_select false excludes column
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, include_in_select: false
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@select_cols = @rodauth.account_select
!@select_cols.include?(:stripe_id) && @select_cols.include?(:redis_id)
#=> true

## Works with other Rodauth features
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :login, :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@select_cols = @rodauth.account_select
@select_cols.include?(:stripe_id)
#=> true

## Helper methods generated with correct names
DB[:accounts].insert(email: 'test1@example.com', stripe_id: 'cus_abc123', redis_id: 'redis-uuid-456')

@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@rodauth.respond_to?(:stripe_id) && @rodauth.respond_to?(:redis_id)
#=> true

## Helper methods return correct values
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@rodauth.instance_variable_set(:@account, DB[:accounts].first)
@rodauth.stripe_id
#=> "cus_abc123"

## Second helper method returns correct value
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@rodauth.instance_variable_set(:@account, DB[:accounts].first)
@rodauth.redis_id
#=> "redis-uuid-456"

## Helper methods handle nil account gracefully
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.stripe_id
#=> nil

## Custom method names work correctly
DB[:accounts].insert(email: 'test2@example.com', stripe_id: 'cus_xyz789')

@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id, method_name: :stripe_customer_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test2@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@rodauth.stripe_customer_id
#=> "cus_xyz789"

## All helper methods listed
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_helper_methods.sort
#=> [:redis_id, :stripe_id]

## column_list returns declared columns
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_list.sort
#=> [:redis_id, :stripe_id]

## column_list empty when no columns declared
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_list
#=> []

## column_config returns configuration hash
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_customer_id, method_name: :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@config_hash = @app_class.allocate.rodauth.external_identity_column_config(:stripe_customer_id)
@config_hash[:column] == :stripe_customer_id && @config_hash[:method_name] == :stripe_id
#=> true

## column_config returns nil for unknown column
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_config(:unknown)
#=> nil

## helper_methods returns method names
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id, method_name: :redis_uuid
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_helper_methods.sort
#=> [:redis_uuid, :stripe_id]

## helper_methods empty when no columns declared
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_helper_methods
#=> []

## column? returns true for declared column name
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column?(:stripe_id)
#=> true

## column? returns true for declared column with custom method name
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_customer_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column?(:stripe_customer_id)
#=> true

## column? returns false for unknown column
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column?(:unknown)
#=> false

## status returns array
DB[:accounts].insert(email: 'test3@example.com', stripe_id: 'cus_status123', redis_id: nil)

@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test3@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@status = @rodauth.external_identity_status
@status.is_a?(Array) && @status.length == 2
#=> true

## status includes required fields
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test3@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@status = @rodauth.external_identity_status
@status_item = @status.first
[:column, :method, :value, :present, :in_select, :in_account, :column_exists].all? { |k| @status_item.key?(k) }
#=> true

## status correctly reports present values
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test3@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@status = @rodauth.external_identity_status
@stripe_status = @status.find { |s| s[:column] == :stripe_id }
@stripe_status[:value] == 'cus_status123' && @stripe_status[:present] == true
#=> true

## status correctly reports nil values
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
    external_identity_column :redis_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test3@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@status = @rodauth.external_identity_status
@redis_status = @status.find { |s| s[:column] == :redis_id }
@redis_status[:value].nil? && @redis_status[:present] == false
#=> true

## status reports column existence
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test3@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@status = @rodauth.external_identity_status
@stripe_status = @status.find { |s| s[:column] == :stripe_id }
@stripe_status[:column_exists]
#=> true

## status handles missing account
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@status = @rodauth.external_identity_status.first
@status[:value].nil? && @status[:present] == false
#=> true

## Checking enabled by default (column doesn't exist raises error)
begin
  Class.new(Roda) do
    plugin :rodauth do
      self.db DB
      enable :external_identity
      external_identity_column :nonexistent
    end

    route { |r| r.rodauth }
  end
  "no error"
rescue ArgumentError => e
  e.message.include?("not found in accounts table")
end
#=> true

## external_identity_on_conflict defaults to :error
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_on_conflict
#=> :error

## external_identity_check_columns defaults to true
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_check_columns
#=> true

## Customize external_identity_on_conflict
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_check_columns false
    external_identity_on_conflict :warn
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_on_conflict
#=> :warn

## Customize external_identity_check_columns to false
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_check_columns false
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_check_columns
#=> false

## Customize external_identity_check_columns to :autocreate
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_check_columns :autocreate
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_check_columns
#=> :autocreate

## Column names with underscores and numbers
@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :oauth2_id
    external_identity_column :api_v2_key
  end

  route do |r|
    r.rodauth
  end
end

@app_class.allocate.rodauth.external_identity_column_list.sort
#=> [:api_v2_key, :oauth2_id]

## Nil values in account hash
DB[:accounts].insert(email: 'test4@example.com', stripe_id: nil)

@app_class = Class.new(Roda) do
  plugin :rodauth do
    self.db DB
    enable :external_identity
    external_identity_column :stripe_id
  end

  route do |r|
    r.rodauth
  end
end

@rodauth = @app_class.allocate.rodauth
@account = DB[:accounts].where(email: 'test4@example.com').first
@rodauth.instance_variable_set(:@account, @account)
@rodauth.stripe_id
#=> nil

DB.disconnect
