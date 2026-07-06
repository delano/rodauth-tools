# spec/rodauth/features/table_guard/table_guard_destructive_modes_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'sequel'
require 'rodauth'
require 'roda'
require 'logger'
require 'stringio'

# Regressions for the destructive sequel modes.
#
# RT-09: :recreate and :drop must operate on the FULL template-derived schema,
#   including the "hidden" tables (account_statuses, account_password_hashes)
#   that have no *_table method. The old code enumerated only the discovered
#   *_table names, so it left the hidden tables in place — which made :recreate
#   crash with "table account_statuses already exists" on the default schema.
#
# RT-08: the drop must run in FK-dependency order inside a single transaction,
#   so a failure part-way through cannot leave a partially dropped schema.
RSpec.describe 'TableGuard destructive sequel modes' do
  let(:db) { Sequel.sqlite }

  after do
    db.disconnect if db
  end

  # :recreate/:drop only run in dev/test — force the environment per-example
  # and restore whatever was there before.
  around do |example|
    previous = ENV.fetch('RACK_ENV', nil)
    ENV['RACK_ENV'] = 'test'
    example.run
  ensure
    if previous.nil?
      ENV.delete('RACK_ENV')
    else
      ENV['RACK_ENV'] = previous
    end
  end

  # A logger that swallows output, so the create/recreate info banners don't
  # spam the test run. We assert on db state, not on log text.
  def null_logger
    Logger.new(StringIO.new)
  end

  def boot_app(sequel_mode:, mode: :silent)
    test_db = db
    quiet = null_logger

    Class.new(Roda) do
      plugin :rodauth do
        db test_db
        enable :login, :logout
        enable :table_guard
        table_guard_logger quiet
        table_guard_mode mode
        table_guard_sequel_mode sequel_mode
      end

      route { |r| r.rodauth }
    end
  end

  # Build the real base schema (accounts + both hidden tables) via the
  # generator's own :create path, so the fixture matches the templates exactly.
  def create_full_schema!
    boot_app(sequel_mode: :create)
    present = db.tables
    missing = %i[accounts account_statuses account_password_hashes].reject { |t| present.include?(t) }
    raise "fixture setup failed, missing: #{missing.inspect} (have #{present.inspect})" unless missing.empty?
  end

  describe ':recreate' do
    it 'recreates the full schema, hidden tables included, when tables pre-exist (RT-09)' do
      create_full_schema!
      expect(db.tables).to include(:account_statuses, :account_password_hashes, :accounts)

      expect { boot_app(sequel_mode: :recreate) }.not_to raise_error

      # Every table — the hidden ones too — is present again afterwards.
      expect(db.tables).to include(:account_statuses, :account_password_hashes, :accounts)
    end

    it 'does not fail with "already exists" on the hidden status table (RT-09)' do
      create_full_schema!

      # With the bug the hidden account_statuses is never dropped, so re-running
      # base.erb raises "table account_statuses already exists". In :raise mode
      # that error is re-raised by handle_sequel_generation's rescue, so a green
      # boot proves the hidden table was dropped before the recreate.
      expect { boot_app(sequel_mode: :recreate, mode: :raise) }.not_to raise_error
      expect(db.table_exists?(:accounts)).to be true
      expect(db.table_exists?(:account_statuses)).to be true
    end

    it 'rolls the whole drop+create back on a mid-drop failure (RT-08)' do
      create_full_schema!
      before = db.tables.sort

      # Fail on the second drop to simulate an interruption part-way through.
      call_count = 0
      allow(db).to receive(:drop_table?).and_wrap_original do |original, *args, **kwargs|
        call_count += 1
        raise Sequel::DatabaseError, 'simulated mid-drop failure' if call_count == 2

        original.call(*args, **kwargs)
      end

      # Silent mode swallows the error in the rescue; the point is that the
      # transaction must leave the schema exactly as it was.
      boot_app(sequel_mode: :recreate)

      expect(db.tables.sort).to eq(before)
    end
  end

  describe ':drop' do
    it 'drops every rodauth table including the hidden ones (RT-09)' do
      create_full_schema!
      expect(db.tables).to include(:account_statuses, :account_password_hashes, :accounts)

      boot_app(sequel_mode: :drop)

      expect(db.tables).not_to include(:accounts)
      expect(db.tables).not_to include(:account_password_hashes)
      expect(db.tables).not_to include(:account_statuses)
    end
  end
end
