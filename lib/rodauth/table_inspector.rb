# lib/rodauth/table_inspector.rb
#
# frozen_string_literal: true

module Rodauth
  # TableInspector dynamically discovers database tables required by enabled Rodauth features.
  #
  # Unlike the old static CONFIGURATION approach, this module inspects a Rodauth instance
  # at runtime to discover which tables are needed based on the features that have been enabled.
  #
  # @example Discover tables from a Rodauth instance
  #   tables = Rodauth::TableInspector.discover_tables(rodauth_instance)
  #   # => { accounts_table: "accounts", otp_keys_table: "account_otp_keys", ... }
  #
  # @example Get detailed table information
  #   info = Rodauth::TableInspector.table_information(rodauth_instance)
  #   # => {
  #   #   accounts_table: {
  #   #     name: "accounts",
  #   #     feature: :base,
  #   #     columns: [:id, :email, :password_hash, ...]
  #   #   },
  #   #   ...
  #   # }
  module TableInspector
    # Discover all table configuration methods and their values from a Rodauth instance
    #
    # @param rodauth_instance [Rodauth::Auth] A Rodauth auth instance
    # @return [Hash<Symbol, String>] Map of method names to table names
    def self.discover_tables(rodauth_instance)
      table_methods = rodauth_instance.methods.select { |m| m.to_s.end_with?('_table') }

      tables = {}
      table_methods.each do |method|
        table_name = rodauth_instance.send(method)
        tables[method] = table_name if table_name.is_a?(String) || table_name.is_a?(Symbol)
      rescue StandardError => e
        # Some table methods might fail if called without proper context
        warn "TableInspector: Unable to call #{method}: #{e.message}" if ENV['RODAUTH_DEBUG']
      end

      tables
    end

    # Build detailed table information including inferred structure
    #
    # @param rodauth_instance [Rodauth::Auth] A Rodauth auth instance
    # @return [Hash<Symbol, Hash>] Detailed information about each table
    def self.table_information(rodauth_instance)
      discovered = discover_tables(rodauth_instance)

      discovered.transform_values do |table_name|
        method_name = discovered.key(table_name)
        feature = infer_feature_from_method(method_name, rodauth_instance)
        template_name = "#{feature}.erb"

        # Check if ERB template exists for this feature
        # If not, mark with warning flag for downstream handling
        template_exists = Rodauth::Tools::Migration.template_exists?(feature)

        info = {
          name: table_name,
          feature: feature,
          template: template_name,
          structure: infer_table_structure(method_name, table_name)
        }

        # Add warning metadata if template is missing
        unless template_exists
          info[:template_missing] = true
          info[:warning] = "No ERB template found for feature: #{feature} (#{template_name})"
        end

        info
      end
    end

    # Infer which feature owns a table based on the method name
    #
    # Uses dynamic feature discovery by checking which enabled Rodauth feature
    # defines the table method. This eliminates the need for hardcoded mappings.
    #
    # @param method_name [Symbol] The table method name (e.g., :otp_keys_table)
    # @param rodauth_instance [Rodauth::Auth] A Rodauth auth instance
    # @return [Symbol, nil] The feature name (e.g., :otp) or nil if not found
    def self.infer_feature_from_method(method_name, rodauth_instance)
      # Special case for base feature tables
      # The accounts_table and password_hash_table are fundamental and always present
      return :base if %w[accounts_table password_hash_table account_password_hash_table].include?(method_name.to_s)

      # Get the Rodauth class (configuration) from the instance
      rodauth_class = rodauth_instance.class

      # Search through enabled features to find which one defines this method
      rodauth_class.features.each do |feature_name|
        feature_module = Rodauth::FEATURES[feature_name]
        next unless feature_module

        # Check if this feature module defines the table method
        return feature_name if feature_module.instance_methods(false).include?(method_name)
      end

      # Fallback: try to infer from method name if not found in any feature
      # This handles edge cases where features might not be fully loaded
      method_str = method_name.to_s.sub(/_table$/, '')
      method_str.to_sym
    end

    # Infer the structure of a table based on patterns
    #
    # This is a simplified placeholder that returns basic metadata.
    # The actual table structure is defined in ERB templates, not hardcoded here.
    #
    # @param method_name [Symbol] The table method name
    # @param table_name [String, Symbol] The actual table name
    # @return [Hash] Table structure metadata (minimal, for compatibility)
    def self.infer_table_structure(_method_name, _table_name)
      # Return minimal structure - the actual schema is in ERB templates
      {
        type: :feature
      }
    end
  end
end
