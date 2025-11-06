# frozen_string_literal: true

# lib/rodauth/features/external_identity.rb

#
# Enable with:
#   enable :external_identity
#
# Configuration (Layer 1 - Basic):
#   external_identity_column :stripe_customer_id
#   external_identity_column :redis_uuid, method_name: :redis_session_key
#   external_identity_on_conflict :warn  # :error, :warn, :skip
#   external_identity_check_columns true  # true (default), false, or :autocreate
#
# Configuration (Layer 2 - Extended Features):
#   external_identity_column :stripe_customer_id,
#     before_create_account: -> { Stripe::Customer.create(email: account[:email]).id },
#     formatter: -> (v) { v.to_s.strip.downcase },
#     validator: -> (v) { v.start_with?('cus_') },
#     verifier: -> (id) { Stripe::Customer.retrieve(id) && !customer.deleted? },
#     handshake: -> (id, token) { session[:oauth_state] == token }
#
# Usage:
#   rodauth.stripe_customer_id  # Auto-generated helper method
#   rodauth.redis_uuid          # Auto-generated helper method
#
# Introspection:
#   rodauth.external_identity_column_list              # [:stripe_customer_id, :redis_uuid]
#   rodauth.external_identity_column_config(:stripe_customer_id)  # {...}
#   rodauth.external_identity_status                   # Complete debug info
#
# Example:
#
#   plugin :rodauth do
#     enable :login, :logout, :external_identity
#
#     # Declare external identity columns
#     external_identity_column :stripe_customer_id
#     external_identity_column :redis_uuid
#
#     # Custom method name
#     external_identity_column :redis_key, method_name: :redis_session_key
#   end
#
#   # In your app
#   rodauth.stripe_customer_id   # => "cus_abc123"
#   rodauth.redis_uuid           # => "550e8400-e29b-41d4-a716-446655440000"

module Rodauth
  Feature.define(:external_identity, :ExternalIdentity) do
    # Configuration methods
    auth_value_method :external_identity_on_conflict, :error
    auth_value_method :external_identity_check_columns, true

    # Public API methods for introspection
    auth_methods(
      :external_identity_column_list,
      :external_identity_column_config,
      :external_identity_helper_methods,
      :external_identity_column?,
      :external_identity_status
    )

    # Layer 2: Validation methods
    auth_methods(
      :validate_external_identity,
      :validate_all_external_identities
    )

    # Layer 2: Verification methods
    auth_methods(
      :verify_external_identity,
      :verify_all_external_identities
    )

    # Layer 2: Handshake methods
    auth_methods(
      :verify_handshake
    )

    # Use auth_cached_method for column configuration
    # This ensures it works in both post_configure and runtime
    auth_cached_method :external_identity_columns_config

    # Add external_identity_column method to Configuration class
    # This makes it available during the configuration block
    configuration_module_eval do
      # Declare an external identity column with optional lifecycle callbacks and database options
      #
      # Creates a helper method to access the column value and automatically includes
      # it in account_select (unless disabled). Supports validation, formatting,
      # verification, and lifecycle hooks.
      #
      # @param column [Symbol] Database column name (required)
      # @param options [Hash] Configuration options
      #
      # @option options [Symbol] :method_name
      #   Custom method name for accessing the column (default: same as column name)
      #
      # @option options [Boolean] :include_in_select (true)
      #   Whether to automatically include in account_select
      #
      # @option options [Proc] :before_create_account
      #   Callback to generate value before account creation. Runs during
      #   before_create_account hook. Value will be formatted and validated
      #   if those callbacks are provided. Block is evaluated in Rodauth instance context.
      #
      # @option options [Proc] :after_create_account
      #   Callback to execute after account creation. Receives the column value
      #   as argument. Block is evaluated in Rodauth instance context.
      #   Useful for provisioning resources or sending notifications.
      #
      # @option options [Proc] :formatter
      #   Transform values (e.g., strip whitespace, normalize case).
      #   Block receives value and should return formatted value.
      #
      # @option options [Proc] :validator
      #   Validate values (must return truthy for valid). Block receives value
      #   and should return true/false. Raises ArgumentError if validation fails.
      #
      # @option options [Proc] :verifier
      #   Health check callback to verify external identity is still valid.
      #   Non-critical - returns false on failure rather than raising.
      #
      # @option options [Proc] :handshake
      #   Security-critical verification callback (e.g., OAuth state verification).
      #   Must return truthy. Raises on failure. Use for callbacks where failure
      #   indicates a security issue.
      #
      # @option options [Symbol, Class] :type (:String)
      #   Sequel column type for migration generation. Valid values:
      #   :String, :Integer, :Bignum, :Boolean, :Date, :DateTime, :Time, :Text
      #
      # @option options [Boolean] :null (true)
      #   Whether column allows NULL values
      #
      # @option options [Object] :default (nil)
      #   Default value for column. Can be a literal value or Proc for dynamic defaults.
      #
      # @option options [Boolean] :unique (false)
      #   Whether column has unique constraint
      #
      # @option options [Integer] :size
      #   Maximum size for String/varchar columns (e.g., 255)
      #
      # @option options [Boolean, Hash] :index (false)
      #   Whether to create index. Use true for simple index,
      #   or Hash for index options like { unique: true, name: :custom_name }
      #
      # @option options [Hash] :sequel
      #   Nested hash for Sequel-specific options (alternative to flat options).
      #   Keys: :type, :null, :default, :unique, :size, :index
      #
      # @example Basic usage
      #   external_identity_column :stripe_customer_id
      #
      # @example With lifecycle callbacks
      #   external_identity_column :stripe_customer_id,
      #     before_create_account: -> { Stripe::Customer.create(email: account[:email]).id },
      #     after_create_account: -> (id) { StripeMailer.welcome(id).deliver }
      #
      # @example With validation and formatting
      #   external_identity_column :api_key,
      #     formatter: -> (v) { v.to_s.strip.downcase },
      #     validator: -> (v) { v =~ /^[a-z0-9]{32}$/ }
      #
      # @example With database constraints
      #   external_identity_column :token,
      #     type: String,
      #     null: false,
      #     unique: true,
      #     size: 64,
      #     index: true
      #
      # @example With nested Sequel options
      #   external_identity_column :session_id,
      #     sequel: {
      #       type: String,
      #       null: false,
      #       default: -> { SecureRandom.hex(32) },
      #       unique: true,
      #       index: { unique: true, name: :idx_session_id }
      #     }
      #
      # @example Complete example with all options
      #   external_identity_column :external_user_id,
      #     method_name: :external_id,
      #     include_in_select: true,
      #     type: String,
      #     null: false,
      #     unique: true,
      #     size: 100,
      #     index: true,
      #     before_create_account: -> { ExternalService.create_user(account[:email]) },
      #     after_create_account: -> (id) { Logger.info("Created external user: #{id}") },
      #     formatter: -> (v) { v.to_s.strip },
      #     validator: -> (v) { v.present? && v.length <= 100 }
      #
      # @raise [ArgumentError] If column is not a Symbol
      # @raise [ArgumentError] If column is not a valid Ruby identifier
      # @raise [ArgumentError] If column is already declared
      # @raise [ArgumentError] If method_name is not a valid Ruby identifier
      #
      # @return [nil]
      def external_identity_column(column, **options)
        # Validate column is a symbol
        unless column.is_a?(Symbol)
          raise ArgumentError, "external_identity_column must be a Symbol, got #{column.class}"
        end

        # Validate column is a valid Ruby identifier
        unless column.to_s =~ /^[a-z_][a-z0-9_]*$/i
          raise ArgumentError, "external_identity_column must be a valid Ruby identifier: #{column}"
        end

        # Default method name is the column name itself
        method_name = options[:method_name] || column

        # Validate method name is valid Ruby identifier
        unless method_name.to_s =~ /^[a-z_][a-z0-9_]*[?!=]?$/i
          raise ArgumentError, "Method name must be a valid Ruby identifier: #{method_name}"
        end

        # Store configuration on the Auth class
        # Use class instance variable to store per-class configuration
        unless @auth.instance_variable_get(:@_external_identity_columns)
          @auth.instance_variable_set(:@_external_identity_columns,
                                      {})
        end
        columns = @auth.instance_variable_get(:@_external_identity_columns)

        # Check for duplicate declarations using column name as key
        raise ArgumentError, "external_identity_column :#{column} already declared" if columns.key?(column)

        # Store configuration (using column as both key and value)
        columns[column] = {
          column: column,
          method_name: method_name,
          include_in_select: options.fetch(:include_in_select, true),
          validate: options[:validate] || false,
          # Layer 2: Lifecycle callbacks
          before_create_account: options[:before_create_account],
          after_create_account: options[:after_create_account],
          formatter: options[:formatter],
          validator: options[:validator],
          verifier: options[:verifier],
          handshake: options[:handshake],
          options: options
        }

        # Define the helper method on the Auth class
        @auth.send(:define_method, method_name) do
          value = account ? account[column] : nil

          # Apply formatter if present (Layer 2)
          config = external_identity_columns_config[column]
          if config && config[:formatter] && value
            instance_exec(value, &config[:formatter])
          else
            value
          end
        end

        nil
      end
    end

    # NOTE: external_identity_column is defined in configuration_module_eval above
    # It's available during configuration but not as an instance method

    # Get list of all declared external identity column names
    #
    # @return [Array<Symbol>] List of column names
    #
    # @example
    #   external_identity_column_list  # => [:stripe_customer_id, :redis_uuid]
    def external_identity_column_list
      external_identity_columns_config.keys
    end

    # Get configuration for a specific external identity column
    #
    # @param column [Symbol] Column name
    # @return [Hash, nil] Configuration hash or nil if not found
    #
    # @example
    #   external_identity_column_config(:stripe_customer_id)
    #   # => {column: :stripe_customer_id, method_name: :stripe_customer_id, ...}
    def external_identity_column_config(column)
      external_identity_columns_config[column]
    end

    # Get list of all generated helper method names
    #
    # @return [Array<Symbol>] List of method names
    #
    # @example
    #   external_identity_helper_methods  # => [:stripe_customer_id, :redis_uuid]
    def external_identity_helper_methods
      external_identity_columns_config.values.map { |config| config[:method_name] }
    end

    # Check if a column has been declared as an external identity
    #
    # @param column [Symbol] Column name
    # @return [Boolean] True if declared
    #
    # @example
    #   external_identity_column?(:stripe_customer_id)  # => true
    #   external_identity_column?(:redis_uuid)          # => true
    #   external_identity_column?(:unknown)             # => false
    def external_identity_column?(column)
      external_identity_columns_config.key?(column)
    end

    # Get complete status information for all declared external identities
    #
    # Useful for debugging and introspection. Shows configuration,
    # current values, and validation status.
    #
    # @return [Array<Hash>] Array of status hashes
    #
    # @example
    #   external_identity_status
    #   # => [
    #   #   {
    #   #     column: :stripe_customer_id,
    #   #     method: :stripe_customer_id,
    #   #     value: "cus_abc123",
    #   #     present: true,
    #   #     in_select: true,
    #   #     in_account: true,
    #   #     column_exists: true
    #   #   },
    #   #   ...
    #   # ]
    def external_identity_status
      current_select = account_select

      external_identity_columns_config.map do |column, config|
        method_name = config[:method_name]

        # Safely get the value
        value = begin
          account ? account[column] : nil
        rescue StandardError
          nil
        end

        # Check if column exists in database
        column_exists = begin
          db.schema(accounts_table).any? { |col| col[0] == column }
        rescue StandardError
          nil # Unknown if can't check
        end

        # Check if column is in select (nil means select all)
        in_select = current_select.nil? || current_select.include?(column)

        {
          column: column,
          method: method_name,
          value: value,
          present: !value.nil?,
          in_select: in_select,
          in_account: account&.key?(column) || false,
          column_exists: column_exists
        }
      end
    end

    # Validate a specific external identity column value
    #
    # Applies formatter (if configured) then validator (if configured).
    # Returns true if valid or no validator configured.
    # Raises ArgumentError if validation fails.
    #
    # @param column [Symbol] Column name
    # @param value [Object] Value to validate
    # @return [Boolean] True if valid
    # @raise [ArgumentError] If validation fails
    #
    # @example
    #   validate_external_identity(:stripe_customer_id, "cus_123")  # => true
    #   validate_external_identity(:stripe_customer_id, "invalid") # => ArgumentError
    def validate_external_identity(column, value)
      config = external_identity_columns_config[column]
      return true unless config
      return true if value.nil? # nil values are not validated

      # Apply formatter if present
      formatted_value = if config[:formatter]
                          instance_exec(value, &config[:formatter])
                        else
                          value
                        end

      # Apply validator if present
      if config[:validator]
        is_valid = instance_exec(formatted_value, &config[:validator])
        raise ArgumentError, "Invalid format for #{column}: #{value.inspect}" unless is_valid
      end

      true
    end

    # Validate all configured external identity columns
    #
    # Checks all columns that have validators configured.
    # Returns hash of column => validation result.
    #
    # @return [Hash<Symbol, Boolean>] Results per column
    #
    # @example
    #   validate_all_external_identities
    #   # => {stripe_customer_id: true, redis_uuid: true}
    def validate_all_external_identities
      results = {}
      external_identity_columns_config.each do |column, config|
        next unless config[:validator]

        value = account ? account[column] : nil
        next if value.nil? # Skip nil values

        validate_external_identity(column, value)
        results[column] = true
      end
      results
    end

    # Verify external identity by checking with external service
    #
    # Health check that verifies the external identity still exists
    # and is valid. Non-critical - returns false on failure rather
    # than raising (except for unhandled exceptions).
    #
    # @param column [Symbol] Column name
    # @return [Boolean] True if verified, false if not or no verifier configured
    #
    # @example
    #   verify_external_identity(:stripe_customer_id)  # => true
    #   verify_external_identity(:deleted_id)          # => false
    def verify_external_identity(column)
      config = external_identity_columns_config[column]
      return true unless config
      return true unless config[:verifier]

      value = account ? account[column] : nil
      return true if value.nil? # Skip nil values

      # Apply formatter if present
      formatted_value = if config[:formatter]
                          instance_exec(value, &config[:formatter])
                        else
                          value
                        end

      # Execute verifier callback
      # Non-critical: catch errors and return false
      begin
        result = instance_exec(formatted_value, &config[:verifier])
        !!result # Ensure boolean
      rescue StandardError => e
        # Log error but don't raise - verification is non-critical
        warn "[external_identity] Verification failed for #{column}: #{e.class} - #{e.message}"
        false
      end
    end

    # Verify all external identities with verifier callbacks
    #
    # Performs health checks on all configured external identities.
    # Skips columns without verifiers or with nil values.
    # Non-critical - continues checking all columns even if some fail.
    #
    # @return [Hash<Symbol, Boolean>] Results per column with verifier
    #
    # @example
    #   verify_all_external_identities
    #   # => {stripe_customer_id: true, github_user_id: false}
    def verify_all_external_identities
      results = {}
      external_identity_columns_config.each do |column, config|
        next unless config[:verifier]

        value = account ? account[column] : nil
        next if value.nil? # Skip nil values

        results[column] = verify_external_identity(column)
      end
      results
    end

    # Verify handshake between external identity and verification token
    #
    # Security-critical verification that checks the external identity
    # value against a verification token (e.g., OAuth state, CSRF token).
    # MUST raise on failure by default - this is security-critical.
    #
    # @param column [Symbol] Column name
    # @param value [Object] External identity value to verify
    # @param token [Object] Verification token (e.g., OAuth state)
    # @return [Boolean] True if handshake verified
    # @raise [RuntimeError] If handshake fails (security-critical)
    #
    # @example OAuth CSRF protection
    #   verify_handshake(:github_user_id, user_info['id'], params['state'])
    #
    # @example Team invite verification
    #   verify_handshake(:team_id, invite.team_id, invite.token)
    def verify_handshake(column, value, token)
      config = external_identity_columns_config[column]

      # Return true if no handshake configured (pass-through)
      return true unless config
      return true unless config[:handshake]

      # Apply formatter if present
      formatted_value = if config[:formatter]
                          instance_exec(value, &config[:formatter])
                        else
                          value
                        end

      # Execute handshake callback
      # Security-critical: MUST raise on failure
      result = instance_exec(formatted_value, token, &config[:handshake])

      raise "Handshake verification failed for #{column}" unless result

      true
    end

    # Generate external identities during account creation
    #
    # Runs in before_create_account hook. For each column with
    # before_create_account callback configured:
    # - Skip if value already set (manual override)
    # - Execute callback to generate value
    # - Apply formatter if configured
    # - Apply validator if configured
    # - Set account column
    #
    # Errors during generation will prevent account creation.
    def before_create_account
      super if defined?(super)
      generate_external_identities
    end

    # Process external identity callbacks after account creation
    #
    # Runs in after_create_account hook. For each column with
    # after_create_account callback configured:
    # - Retrieve current column value
    # - Execute callback with column value as argument
    #
    # Useful for:
    # - Provisioning external resources
    # - Sending notifications with external IDs
    # - Triggering webhooks
    # - Logging/auditing
    def after_create_account
      super if defined?(super)
      process_after_create_callbacks
    end

    # Validation hook - runs after configuration is complete
    #
    # Validates configuration and provides helpful warnings/errors
    def post_configure
      super if defined?(super)

      # Wrap account_select to add external identity columns
      setup_account_select_wrapper

      # Check columns based on configuration
      case external_identity_check_columns
      when true
        # Check existence and raise if missing
        check_columns_exist!
      when :autocreate
        # Check existence and inform table_guard if missing
        check_and_autocreate_columns!
      when false
        # Skip checking entirely
      else
        raise ArgumentError,
              "external_identity_check_columns must be true, false, or :autocreate, got: #{external_identity_check_columns.inspect}"
      end

      # Always check that columns are included in account_select if they should be
      validate_account_select_inclusion!
    end

    private

    # Wrap account_select method to add external identity columns
    #
    # This runs in post_configure after all configuration is complete.
    # It wraps the existing account_select method (whether default nil or
    # user-configured) to add our columns.
    def setup_account_select_wrapper
      # Get current account_select value at configuration time
      # (calling the method gets the configured value)
      current_select = account_select

      # Get columns to add
      columns_to_add = external_identity_columns_config.select do |_name, config|
        config[:include_in_select]
      end.keys

      # Return early if no columns to add
      return if columns_to_add.empty?

      # Redefine account_select on the Auth subclass to wrap it
      #
      # NOTE: We use self.class.send(:define_method) rather than define_singleton_method
      # because in Rodauth's architecture, each configuration gets its own Rodauth::Auth
      # SUBCLASS (not just instance). Defining on self.class ensures the method is available
      # on all runtime instances of this particular Auth subclass, which is what we need.
      # Using define_singleton_method would only affect the temporary configuration instance.
      #
      # Capturing current_select at configuration time (rather than calling account_select
      # dynamically) is intentional - it preserves the configured state from post_configure,
      # which runs after all user configuration is complete. This prevents infinite recursion
      # and ensures we build on the base configuration's account_select value.
      self.class.send(:define_method, :account_select) do
        # Use the captured value from configuration time
        cols = current_select

        # If configured value is nil, preserve that (select all columns)
        return nil if cols.nil?

        # Normalize to array
        cols = case cols
               when Array then cols.dup
               else [cols]
               end

        # Add external identity columns (idempotent via include? check)
        columns_to_add.each do |column|
          cols << column unless cols.include?(column)
        end

        cols
      end
    end

    # Generate external identities for columns with before_create_account callbacks
    #
    # Called during before_create_account hook
    def generate_external_identities
      external_identity_columns_config.each do |column, config|
        next unless config[:before_create_account]

        # Skip if value already set (manual override)
        next if account[column]

        # Execute generator callback
        generated_value = instance_exec(&config[:before_create_account])

        # Skip if generator returned nil (intentionally not setting)
        next if generated_value.nil?

        # Apply formatter if configured
        value = if config[:formatter]
                  instance_exec(generated_value, &config[:formatter])
                else
                  generated_value
                end

        # Apply validator if configured
        if config[:validator]
          is_valid = instance_exec(value, &config[:validator])
          raise ArgumentError, "Generated value for #{column} failed validation: #{value.inspect}" unless is_valid
        end

        # Set the account column
        account[column] = value
      end
    end

    # Process after_create_account callbacks for external identity columns
    #
    # Called during after_create_account hook. For each column with
    # after_create_account callback configured, execute the callback
    # with the current column value as argument.
    def process_after_create_callbacks
      external_identity_columns_config.each do |column, config|
        next unless config[:after_create_account]

        # Get current value from account
        current_value = account[column]

        # Execute callback with current value
        instance_exec(current_value, &config[:after_create_account])
      end
    end

    # Internal method called by auth_cached_method
    #
    # Retrieves the storage hash for external identity configurations from the Auth class
    # This is called lazily per-instance and cached
    #
    # @return [Hash] Configuration hash from the Auth class
    def _external_identity_columns_config
      # Get from class instance variable set during configuration
      self.class.instance_variable_get(:@_external_identity_columns) || {}
    end

    # Check that declared columns exist in the database
    #
    # Runs when external_identity_check_columns is true
    #
    # @raise [ArgumentError] If columns are missing
    def check_columns_exist!
      missing = find_missing_columns
      return if missing.empty?

      column_list = missing.map { |col| ":#{col}" }.join(', ')
      raise ArgumentError, "External identity columns not found in #{accounts_table} table: #{column_list}. " \
                           'Add columns to database, set external_identity_check_columns to false, or use :autocreate mode.'
    end

    # Check columns and inform table_guard if any are missing
    #
    # Runs when external_identity_check_columns is :autocreate
    def check_and_autocreate_columns!
      missing = find_missing_columns
      return if missing.empty?

      # If table_guard is enabled, inform it about missing columns
      raise ArgumentError, build_external_identity_columns_error(missing) unless respond_to?(:table_guard_mode)

      # Register missing external identity columns with table_guard
      register_external_columns_with_table_guard(missing)

      # No table_guard available - provide helpful error with migration code
    end

    # Find columns that don't exist in the database
    #
    # @return [Array<Symbol>] Array of missing column names
    def find_missing_columns
      return [] unless db # Skip if no database available

      schema = begin
        db.schema(accounts_table)
      rescue StandardError
        # Can't check - database might not exist yet
        return []
      end

      column_names = schema.map { |col| col[0] }

      missing = []
      external_identity_columns_config.each do |column, _config|
        missing << column unless column_names.include?(column)
      end

      missing
    end

    # Register missing external identity columns with table_guard
    #
    # @param missing [Array<Symbol>] Array of missing column names
    def register_external_columns_with_table_guard(missing)
      # Add missing columns to table_guard's configuration
      # This allows table_guard to generate migrations or create columns
      # based on its sequel_mode setting

      missing.each do |column|
        # Get column configuration
        config = external_identity_columns_config[column]

        # Build column definition with Sequel options
        column_def = {
          name: column,
          type: extract_column_type(config),
          null: extract_column_null(config),
          default: extract_column_default(config),
          unique: extract_column_unique(config),
          size: extract_column_size(config),
          index: extract_column_index(config),
          feature: :external_identity
        }

        # Register column with table_guard
        # table_guard will validate and optionally create based on its configuration
        register_required_column(accounts_table, column_def)
      end

      # Trigger table_guard's validation which will handle creation/logging
      # based on table_guard_mode and table_guard_sequel_mode
      #
      # Since external_identity's post_configure runs after table_guard's,
      # we need to explicitly trigger the checking again now that we've
      # registered our columns
      #
      # Check if we should handle columns: either validation is enabled OR sequel_mode is set
      # (sequel_mode works even in silent mode since it indicates intent to create/generate)
      return unless should_check_tables? || table_guard_sequel_mode

      # Get the missing columns we just registered
      missing_cols = missing_columns
      return if missing_cols.empty?

      # Handle columns according to table_guard's configuration
      # (skip validation in silent mode, but allow sequel operations)
      handle_column_guard_mode(missing_cols) if should_check_tables?

      # Generate/create columns if sequel mode is configured
      handle_sequel_generation([], missing_cols) if table_guard_sequel_mode
    end

    # Extract column type from configuration
    #
    # Checks in order: nested sequel hash, flat options, default to String
    #
    # @param config [Hash] Column configuration
    # @return [Class] Column type (Integer, String, etc.)
    def extract_column_type(config)
      config.dig(:options, :sequel, :type) ||
        config.dig(:options, :type) ||
        String
    end

    # Extract column null setting from configuration
    #
    # @param config [Hash] Column configuration
    # @return [Boolean] Whether column allows NULL
    def extract_column_null(config)
      # Check nested sequel hash first, then flat options
      if config.dig(:options, :sequel)&.key?(:null)
        config.dig(:options, :sequel, :null)
      elsif config.dig(:options)&.key?(:null)
        config.dig(:options, :null)
      else
        true # External IDs are optional by default
      end
    end

    # Extract column default value from configuration
    #
    # @param config [Hash] Column configuration
    # @return [Object, nil] Default value or nil
    def extract_column_default(config)
      config.dig(:options, :sequel, :default) ||
        config.dig(:options, :default)
    end

    # Extract column unique setting from configuration
    #
    # @param config [Hash] Column configuration
    # @return [Boolean] Whether column has unique constraint
    def extract_column_unique(config)
      config.dig(:options, :sequel, :unique) ||
        config.dig(:options, :unique) ||
        false
    end

    # Extract column size from configuration
    #
    # @param config [Hash] Column configuration
    # @return [Integer, nil] Column size or nil
    def extract_column_size(config)
      config.dig(:options, :sequel, :size) ||
        config.dig(:options, :size)
    end

    # Extract column index setting from configuration
    #
    # @param config [Hash] Column configuration
    # @return [Boolean, Hash] Index configuration
    def extract_column_index(config)
      config.dig(:options, :sequel, :index) ||
        config.dig(:options, :index) ||
        false
    end

    # Build error message for missing external identity columns with migration example
    #
    # @param missing [Array<Symbol>] Array of missing column names
    # @return [String] Error message with migration code
    def build_external_identity_columns_error(missing)
      column_list = missing.map { |col| ":#{col}" }.join(', ')

      migration_code = generate_external_identity_migration_code(missing)

      <<~ERROR
        External identity columns not found in #{accounts_table} table: #{column_list}

        With external_identity_check_columns set to :autocreate but table_guard not enabled.

        Either:
        1. Enable table_guard feature with sequel_mode to auto-create
        2. Create migration manually:

        #{migration_code}

        3. Set external_identity_check_columns to false to skip checking
      ERROR
    end

    # Generate migration code for missing external identity columns
    #
    # @param missing [Array<Symbol>] Array of missing column names
    # @return [String] Sequel migration code
    def generate_external_identity_migration_code(missing)
      lines = ['Sequel.migration do', '  up do', "    alter_table :#{accounts_table} do"]

      missing.each do |column|
        lines << "      add_column :#{column}, String"
      end

      lines += ['    end', '  end', '', '  down do', "    alter_table :#{accounts_table} do"]

      missing.each do |column|
        lines << "      drop_column :#{column}"
      end

      lines += ['    end', '  end', 'end']

      lines.join("\n")
    end

    # Validate that columns are included in account_select if they should be
    #
    # Provides helpful warnings if configuration might not work as expected
    def validate_account_select_inclusion!
      current_select = account_select
      return unless current_select # Skip if account_select not defined (e.g., no login feature)

      missing = []
      external_identity_columns_config.each do |column, config|
        missing << ":#{column}" if config[:include_in_select] && !current_select.include?(column)
      end

      return if missing.empty?

      warn "[external_identity] WARNING: Columns #{missing.join(", ")} marked for inclusion " \
           'but not in account_select. This may indicate a configuration order issue. ' \
           'The feature should have added them automatically.'
    end
  end
end
