# lib/rodauth/template_inspector.rb

require 'erb'
require 'dry/inflector'

module Rodauth
  # Inspects ERB templates to extract table information
  #
  # This module solves the "hidden tables" problem where ERB templates create
  # tables that don't have corresponding *_table methods in Rodauth features.
  # For example, base.erb creates account_statuses and account_password_hashes
  # tables, but only accounts_table method exists.
  #
  # By evaluating ERB templates, we can discover ALL tables that will be created,
  # which is essential for generating complete DROP statements.
  module TemplateInspector
    # Extract table names from a single ERB template
    #
    # @param feature [Symbol] Feature name (e.g., :base, :verify_account)
    # @param table_prefix [String] Table prefix to use (default: 'account')
    # @param db_type [Symbol] Database type for conditional logic (default: :postgres)
    # @return [Array<Symbol>] Array of table names that will be created
    def self.extract_tables_from_template(feature, table_prefix: 'account', db_type: :postgres)
      template_path = template_path_for_feature(feature)
      return [] unless File.exist?(template_path)

      template_content = File.read(template_path)

      # Create binding context with necessary methods
      context = BindingContext.new(table_prefix, db_type)

      # Evaluate ERB template
      begin
        rendered = ERB.new(template_content, trim_mode: '-').result(context.get_binding)
      rescue => e
        warn "Failed to evaluate template for #{feature}: #{e.message}"
        return []
      end

      # Extract table names from create_table calls
      # Matches: create_table(:table_name) or create_table?(:table_name)
      tables = rendered.scan(/create_table\??[:(\s]+:?(\w+)/).flatten

      tables.map(&:to_sym).uniq
    end

    # Get all tables for a set of features
    #
    # @param features [Array<Symbol>] Feature names
    # @param table_prefix [String] Table prefix to use
    # @param db_type [Symbol] Database type
    # @return [Array<Symbol>] Array of all table names across features
    def self.all_tables_for_features(features, table_prefix: 'account', db_type: :postgres)
      tables = []

      features.each do |feature|
        feature_tables = extract_tables_from_template(
          feature,
          table_prefix: table_prefix,
          db_type: db_type
        )
        tables.concat(feature_tables)
      end

      tables.uniq
    end

    # Get template path for a feature
    #
    # @param feature [Symbol] Feature name
    # @return [String] Absolute path to ERB template
    def self.template_path_for_feature(feature)
      File.join(__dir__, 'tools', 'migration', 'sequel', "#{feature}.erb")
    end

    # Binding context for ERB evaluation
    #
    # Provides minimal methods needed for ERB template evaluation without
    # requiring a full database connection or Rodauth instance.
    class BindingContext
      attr_reader :table_prefix

      def initialize(table_prefix, db_type)
        @table_prefix = table_prefix
        @db_type = db_type
        @inflector = Dry::Inflector.new
      end

      # Pluralize a word using dry-inflector
      def pluralize(word)
        @inflector.pluralize(word.to_s)
      end

      # Mock database object for template evaluation
      #
      # Templates check db.database_type and db.supports_partial_indexes?
      # to generate database-specific code.
      def db
        @db ||= MockDatabase.new(@db_type)
      end

      # Get binding for ERB evaluation
      def get_binding
        binding
      end

      # Mock Sequel database for ERB templates
      class MockDatabase
        attr_reader :database_type

        def initialize(db_type)
          @database_type = db_type
        end

        def supports_partial_indexes?
          # PostgreSQL and SQLite support partial indexes
          [:postgres, :sqlite].include?(@database_type)
        end

        # Stub other methods that might be called in templates
        def method_missing(method, *args, &block)
          # Return a safe default for unknown methods
          nil
        end

        def respond_to_missing?(method, include_private = false)
          true
        end
      end
    end
  end
end
