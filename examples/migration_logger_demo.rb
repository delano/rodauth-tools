#!/usr/bin/env ruby
# examples/migration_logger_demo.rb
#
# frozen_string_literal: true

# Demonstration of logger suppression during migrations
#
# Shows the difference between running migrations with and without
# logger suppression to eliminate confusing "no such table" errors.

require 'bundler/setup'
require 'sequel'
require 'logger'
require 'tempfile'

# Load Sequel migration extension
Sequel.extension :migration

# Create temporary migration directory
migration_dir = Dir.mktmpdir
at_exit { FileUtils.rm_rf(migration_dir) }

# Create a simple migration with create_table?
migration_file = File.join(migration_dir, '001_create_test.rb')
File.write(migration_file, <<~RUBY)
  Sequel.migration do
    up do
      create_table?(:test_accounts) do
        primary_key :id
        String :email, null: false
      end
    end

    down do
      drop_table?(:test_accounts)
    end
  end
RUBY

puts "=" * 70
puts "Migration Logger Suppression Demo"
puts "=" * 70
puts

# Demo 1: WITHOUT suppression
puts "1. WITHOUT suppression (confusing errors appear):"
puts "-" * 70
DB1 = Sequel.sqlite
DB1.loggers << Logger.new($stdout)

Sequel::Migrator.run(DB1, migration_dir, use_transactions: true)
puts

# Demo 2: WITH suppression
puts "2. WITH suppression (clean output):"
puts "-" * 70
DB2 = Sequel.sqlite
DB2.loggers << Logger.new($stdout)

# Suppress logger during migration
original_loggers = DB2.loggers.dup
DB2.loggers.clear
Sequel::Migrator.run(DB2, migration_dir, use_transactions: true)
DB2.loggers.clear
original_loggers.each { |logger| DB2.loggers << logger }

puts "   Migration completed successfully"
puts

puts "=" * 70
puts "Result: Both approaches work, but #2 has cleaner logs"
puts "=" * 70
