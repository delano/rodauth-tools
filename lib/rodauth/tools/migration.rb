# lib/rodauth/tools/migration.rb
#
# frozen_string_literal: true

require 'erb'
require 'dry/inflector'

module Rodauth
  module Tools
    # Sequel migration generator for Rodauth database tables.
    #
    # @deprecated This static migration generator is deprecated in favor of
    #   the dynamic table_guard feature with sequel generation modes.
    #   Use table_guard_sequel_mode instead for automatic migration generation.
    #
    # Generates migrations for Sequel ORM, supporting
    # PostgreSQL, MySQL, and SQLite databases.
    #
    # @example Generate a migration (DEPRECATED)
    #   generator = Rodauth::Tools::Migration.new(
    #     features: [:base, :verify_account, :otp],
    #     prefix: "account",
    #     db_adapter: :postgresql
    #   )
    #
    #   generator.generate # => migration content
    #
    # @example Use table_guard instead (RECOMMENDED)
    #   plugin :rodauth do
    #     enable :base, :verify_account, :otp, :table_guard
    #     table_guard_sequel_mode :migration
    #   end
    class Migration
      attr_reader :features, :prefix, :db_adapter, :db

      # Initialize the migration generator
      #
      # @param features [Array<Symbol>] List of Rodauth features to generate tables for
      # @param prefix [String] Table name prefix (default: "account")
      # @param db_adapter [Symbol] Database adapter (:postgresql, :mysql2, :sqlite3)
      # @param db [Sequel::Database] Sequel database connection
      def initialize(features:, prefix: nil, db_adapter: nil, db: nil)
        @features = Array(features).map(&:to_sym)
        @prefix = prefix
        @db_adapter = db_adapter&.to_sym
        @db = db || create_mock_db

        validate_features!
        validate_feature_templates!
      end

      # Generate the migration content
      #
      # @return [String] Complete migration file content
      def generate
        features
          .map { |feature| load_template(feature) }
          .map { |content| evaluate_erb(content) }
          .join("\n")
      end

      # Execute CREATE TABLE operations directly against the database
      #
      # This evaluates the ERB templates and executes the resulting
      # Sequel migration code against the provided database connection.
      #
      # @param db [Sequel::Database] Database connection
      # @return [void]
      def execute_create_tables(db)
        # Update the db reference for template binding
        @db = db

        # Generate migration code from ERB templates
        migration_code = generate

        # Load Sequel's migration extension
        require 'sequel/extensions/migration'

        # Wrap in Sequel.migration block and execute
        # NOTE: Using eval here is appropriate because:
        # 1. The code is generated from our own trusted ERB templates
        # 2. This is how Sequel migrations work - they're Ruby DSL code
        # 3. The alternative would require re-implementing Sequel's migration DSL
        migration = eval(<<~RUBY, binding, __FILE__, __LINE__ + 1)
          Sequel.migration do
            up do
              #{migration_code}
            end
          end
        RUBY

        # Apply the migration
        migration.apply(db, :up)
      end

      # Get the migration name
      #
      # @return [String] Migration name
      def migration_name
        parts = ['create_rodauth']
        parts << prefix if prefix && prefix != 'account'
        parts.concat(features)
        parts.join('_')
      end

      # Check if an ERB template exists for a given feature
      #
      # @param feature [Symbol] Feature name
      # @return [Boolean] True if template exists
      def self.template_exists?(feature)
        template_path = File.join(__dir__, 'migration', 'sequel', "#{feature}.erb")
        File.exist?(template_path)
      end

      private

      def validate_features!
        return if features.any?

        raise ArgumentError, 'No features specified'
      end

      def validate_feature_templates!
        features.each do |feature|
          template_path = File.join(template_directory, "#{feature}.erb")
          raise ArgumentError, "No migration template for feature: #{feature}" unless File.exist?(template_path)
        end
      end

      def create_mock_db
        adapter = @db_adapter || :postgres
        MockSequelDatabase.new(adapter)
      end

      def load_template(feature)
        template_path = File.join(template_directory, "#{feature}.erb")
        File.read(template_path)
      end

      def evaluate_erb(content)
        ERB.new(content, trim_mode: '-').result(binding)
      end

      def template_directory
        File.join(__dir__, 'migration', 'sequel')
      end

      def table_prefix
        (@prefix || 'account').to_s
      end

      # Helper method for templates to pluralize table names
      def pluralize(str)
        inflector.pluralize(str)
      end

      # Helper method for JSON column type based on database type
      def json_type
        case db.database_type
        when :postgres
          :jsonb
        when :sqlite, :mysql
          :json
        else
          String
        end
      end

      # Cached inflector instance
      def inflector
        @inflector ||= Dry::Inflector.new
      end

      # Mock database object for Sequel templates when no real db is provided
      class MockSequelDatabase
        attr_reader :database_type

        def initialize(adapter = :postgres)
          @database_type = adapter
        end

        def supports_partial_indexes?
          %i[postgres sqlite].include?(database_type)
        end
      end
    end
  end
end
