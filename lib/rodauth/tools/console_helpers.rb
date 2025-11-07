# lib/rodauth/tools/console_helpers.rb
#
# frozen_string_literal: true

module Rodauth
  module Tools
    # Console helper methods for inspecting Rodauth table configuration
    #
    # Usage in console:
    #   require 'rodauth/tools/console_helpers'
    #   include Rodauth::Tools::ConsoleHelpers
    #   rodauth.table_configuration
    #
    # Or use the convenience loader:
    #   Rodauth::Tools::ConsoleHelpers.load!(rodauth_instance)
    module ConsoleHelpers
      # Get or create a Rodauth instance
      #
      # Override this method in your console script to provide the actual instance
      def rodauth
        @rodauth ||= begin
          raise NotImplementedError, 'You must define a `rodauth` method that returns a Rodauth instance'
        end
      end

      # Get discovered table configuration
      def config
        rodauth.table_configuration
      end

      # Get missing tables
      def missing
        rodauth.missing_tables
      end

      # List all required table names
      def tables
        rodauth.list_all_required_tables
      end

      # Get detailed status for each table
      def status
        rodauth.table_status
      end

      # Access database connection
      def db
        rodauth.db if rodauth.respond_to?(:db)
      end

      # Pretty-print table configuration
      def show_config
        puts "\n=== Table Configuration ==="
        config.each do |method, info|
          puts "\n#{method}:"
          puts "  Table: #{info[:name]}"
          puts "  Feature: #{info[:feature]}"
          puts "  Type: #{info[:structure][:type]}"
          puts "  Exists: #{rodauth.table_exists?(info[:name])}"
        end
        nil
      end

      # Pretty-print missing tables
      def show_missing
        puts "\n=== Missing Tables ==="
        if missing.empty?
          puts '✓ All tables exist!'
        else
          missing.each do |info|
            puts "✗ #{info[:table]} (feature: #{info[:feature]})"
          end
        end
        nil
      end

      # Pretty-print table status
      def show_status
        puts "\n=== Table Status ==="
        status.each do |info|
          marker = info[:exists] ? '✓' : '✗'
          puts "#{marker} #{info[:table].to_s.ljust(30)} (#{info[:feature]})"
        end
        nil
      end

      # Create missing tables immediately
      def create_tables!
        puts "\n=== Creating Missing Tables ==="
        missing_list = missing
        if missing_list.empty?
          puts '✓ All tables already exist!'
          return
        end

        generator = Rodauth::SequelGenerator.new(missing_list, rodauth)
        generator.execute_creates(db)
        puts "✓ Created #{missing_list.size} table(s)"
        show_status
        nil
      end

      # Display generated migration code
      def show_migration
        puts "\n=== Generated Migration ==="
        missing_list = missing
        if missing_list.empty?
          puts '✓ All tables exist - no migration needed'
          return
        end

        generator = Rodauth::SequelGenerator.new(missing_list, rodauth)
        puts generator.generate_migration
        nil
      end

      # Show help message
      def help
        puts <<~HELP

          🔍 Rodauth Console Helpers
          ============================

          rodauth          # Get Rodauth instance
          config           # Get discovered table configuration
          missing          # Get missing tables
          tables           # List all required table names
          status           # Get detailed status for each table
          db               # Access Sequel database connection

          show_config      # Pretty-print table configuration
          show_missing     # Pretty-print missing tables
          show_status      # Pretty-print table status
          create_tables!   # Create all missing tables
          show_migration   # Display generated migration code

          help             # Show this help

          Examples:
          ---------
          config.keys                         # See all table methods
          missing.size                        # How many tables are missing?
          rodauth.table_exists?(:accounts)    # Check specific table
          db.tables                           # See what's in the database

        HELP
        nil
      end

      # Class method to extend a context with helpers and set up rodauth method
      #
      # @param rodauth_instance [Rodauth::Auth] Rodauth instance
      # @return [Module] Extended module
      def self.extended(base)
        puts "\n✓ Rodauth console helpers loaded!"
        base.help if base.respond_to?(:help)
      end
    end
  end
end
