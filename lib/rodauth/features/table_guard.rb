# lib/rodauth/features/table_guard.rb
#
# frozen_string_literal: true

# Ensure dependencies are loaded (they should be via require 'rodauth/tools')
require_relative '../table_inspector' unless defined?(Rodauth::TableInspector)
require_relative '../sequel_generator' unless defined?(Rodauth::SequelGenerator)

#
# Enable with:
#   enable :table_guard
#
# Configuration:
#   table_guard_mode :warn    # :warn, :error, :silent, :skip, :raise, :halt/:exit, or block
#   table_guard_sequel_mode :log    # :log, :migration, :create, :sync
#   table_guard_skip_tables [:some_table]  # Skip checking specific tables
#
# Logging:
#   def logger; MyLogger; end              # Standard Rodauth logger (recommended)
#   table_guard_logger MyLogger            # Feature-specific logger (alternative)
#
# Example modes:
#
#   # Warn but continue
#   table_guard_mode :warn
#
#   # Error log but continue
#   table_guard_mode :error
#
#   # Raise exception for handling upstream
#   table_guard_mode :raise
#
#   # Halt/exit startup (not recommended for multi-tenant)
#   table_guard_mode :halt
#
#   # Custom handling with block
#   table_guard_mode do |missing, config|
#     TenantLogger.log_missing_tables(current_tenant, missing)
#   end
#
# Sequel generation modes:
#
#   # Log migration code to logger
#   table_guard_sequel_mode :log
#
#   # Generate migration file
#   table_guard_sequel_mode :migration
#
#   # Create tables immediately (JIT)
#   table_guard_sequel_mode :create
#
#   # Drop and recreate missing tables (dev/test only)
#   table_guard_sequel_mode :sync
#
#   # Drop and recreate ALL tables every startup (dev/test only)
#   table_guard_sequel_mode :recreate

module Rodauth
  Feature.define(:table_guard, :TableGuard) do
    # Configuration methods
    auth_value_method :table_guard_mode, nil
    auth_value_method :table_guard_sequel_mode, nil
    auth_value_method :table_guard_skip_tables, []
    auth_value_method :table_guard_check_columns?, true
    auth_value_method :table_guard_migration_path, 'db/migrate'
    auth_value_method :table_guard_logger, nil
    auth_value_method :table_guard_logger_name, nil # For SemanticLogger integration

    # Public API methods
    auth_methods(
      :check_required_tables!,
      :missing_tables,
      :missing_columns,
      :all_table_methods,
      :list_all_required_tables,
      :list_all_required_columns,
      :table_status,
      :column_status,
      :register_required_column
    )

    # Use auth_cached_method for table_configuration so it's computed
    # lazily per-instance and cached. This ensures it works in both:
    # - Normal web request flow (post_configure runs on throwaway instance)
    # - Console interrogation (new instances need access to configuration)
    auth_cached_method :table_configuration

    # Use auth_cached_method for column_requirements so it persists across instances
    # Column requirements are registered dynamically by features like external_identity
    auth_cached_method :column_requirements

    # Runs after configuration is complete
    #
    # Checks tables based on mode. Note: post_configure runs on a throwaway
    # instance during initial configuration (see Rodauth.configure line 66),
    # so we can't rely on instance variables persisting. Use auth_cached_method
    # for any data needed by later instances.
    def post_configure
      super if defined?(super)

      # Check tables based on mode (uses lazy-loaded table_configuration)
      # Always check if sequel_mode is set (even in silent mode), since sequel_mode
      # indicates we want to create/generate even if we don't want validation messages
      check_required_tables! if should_check_tables? || table_guard_sequel_mode
    end

    # Override hook_action to check table status
    #
    # [Reviewer note] Do not remove this method even though it does nothing by default.
    #
    # @param [Symbol] hook_type :before or :after
    # @param [Symbol] action :login, :logout, etc.
    def hook_action(hook_type, action)
      super # does nothing by default
    end

    # Determine if table checking should run
    #
    # Returns true unless mode is :skip, :silent, or nil
    def should_check_tables?
      # Check if table_guard_mode is defined as a block (has parameters)
      # by checking the method's arity. If arity > 0, it's a block that
      # expects arguments and we can't call it without args.
      mode_method = method(:table_guard_mode)

      # If method expects parameters (arity > 0), it's a custom block handler
      return true if mode_method.arity > 0

      # Safe to call the method - it either returns a symbol or is a 0-arity block
      mode_value = table_guard_mode

      # Always check if mode is a Proc (0-arity custom handler)
      return true if mode_value.is_a?(Proc)

      # Check if mode indicates checking is enabled
      mode_value != :silent && mode_value != :skip && !mode_value.nil?
    end

    # Internal method called by auth_cached_method :table_configuration
    #
    # Discovers and returns table configuration. This is called lazily
    # per-instance and the result is cached in @table_configuration.
    #
    # @return [Hash<Symbol, Hash>] Table configuration
    def _table_configuration
      config = Rodauth::TableInspector.table_information(self)
      rodauth_debug("[table_guard] Discovered #{config.size} required tables") if ENV['RODAUTH_DEBUG']
      config
    end

    # Internal method called by auth_cached_method :column_requirements
    #
    # Initializes and returns column requirements hash. This is called lazily
    # per-instance and the result is cached in @column_requirements.
    #
    # Structure: { table_name => { column_name => { type:, null:, feature: } } }
    #
    # @return [Hash<Symbol, Hash<Symbol, Hash>>] Column requirements by table
    def _column_requirements
      {}
    end

    # Check required tables and handle based on mode
    #
    # This is the main entry point for table validation
    def check_required_tables!
      missing = missing_tables
      missing_cols = missing_columns

      # Special case: :recreate and :drop modes always run, even when no tables are missing
      if missing.empty? && missing_cols.empty? && !%i[recreate drop].include?(table_guard_sequel_mode)
        rodauth_info('')
        rodauth_info('─' * 50)
        rodauth_info('✅ TableGuard: All required tables and columns exist')
        rodauth_info("   #{table_configuration.size} tables validated successfully")
        if list_all_required_columns.any?
          rodauth_info("   #{list_all_required_columns.size} columns validated successfully")
        end
        rodauth_info('─' * 50)
        rodauth_info('')
        return
      end

      # Handle based on validation mode (unless recreate/drop mode which handles its own validation)
      handle_table_guard_mode(missing) unless %i[recreate drop].include?(table_guard_sequel_mode)

      # Handle missing columns separately if validation mode passes
      handle_column_guard_mode(missing_cols) if missing_cols.any? && !%i[recreate
                                                                         drop].include?(table_guard_sequel_mode)

      # Generate Sequel if configured
      handle_sequel_generation(missing, missing_cols) if table_guard_sequel_mode
    end

    # Get list of tables that are missing
    #
    # @return [Array<Hash>] Array of missing table information
    def missing_tables
      result = []

      # Fetch the set of existing table names ONCE for this pass and reuse it
      # across every table check, instead of running a catalog query per table
      # (N+1). See #table_exists? for why the set is not cached on the instance.
      existing = existing_table_names

      table_configuration.each do |method, info|
        table_name = info[:name]
        next if table_exists?(table_name, existing)

        result << {
          method: method,
          table: table_name,
          feature: info[:feature],
          structure: info[:structure]
        }
      end

      result
    end

    # Get all table method names ending in _table
    #
    # @return [Array<Symbol>] Table method names
    def all_table_methods
      methods.select { |m| m.to_s.end_with?('_table') }
    end

    # Check if a table exists in the database
    #
    # For the common case (an unqualified base table in the default schema) this
    # matches against the database's table/view list rather than probing each
    # table with a SELECT. Sequel's db.table_exists? probe logs the "no such
    # table" exception before catching it internally, which an earlier
    # implementation worked around by clearing and restoring the shared
    # db.loggers array around the call. That mutation of shared connection state
    # was not thread-safe: a concurrent query (e.g. when table_status/
    # column_status are called at runtime) could execute while logging was
    # disabled. Matching against the listed names avoids the failed probe
    # entirely, so no logger suppression — and no shared-state mutation — is
    # needed. Views are included (via db.views when the adapter supports it)
    # because a Rodauth table can legitimately be backed by a view, which
    # db.tables alone omits on most adapters.
    #
    # Schema-qualified names (a Symbol like :auth__accounts, a
    # Sequel::SQL::QualifiedIdentifier, or a Sequel.qualify(...) result) are NOT
    # reflected in db.tables (which returns unqualified names from the current
    # search_path), so they take a separate, schema-aware path: we probe with
    # db.table_exists?. That probe can emit Sequel's error-log noise, but it is
    # confined to this rare qualified path and never fires for the common
    # unqualified case that #116 was about.
    #
    # The optional existing_tables argument lets looping callers
    # (missing_tables, table_status) build the existing-name Set ONCE per
    # introspection pass and reuse it, avoiding N catalog queries. When omitted
    # (the single-name public call) a fresh set is fetched — the set is
    # deliberately NOT cached on the instance so runtime introspection does not
    # go stale if tables are created after boot.
    #
    # NOTE: On a genuine error we still fail open (assume the table exists) to
    # preserve current behavior; switching this to fail closed is tracked in the
    # table_guard hardening follow-up (issue #116).
    #
    # @param table_name [String, Symbol, Sequel::SQL::QualifiedIdentifier] Table name
    # @param existing_tables [Set<Symbol>, nil] Pre-fetched existing table names
    # @return [Boolean] True if table exists
    def table_exists?(table_name, existing_tables = nil)
      # Symbol/String names may be skipped by configuration. A
      # QualifiedIdentifier does not respond to to_sym, so guard the lookup.
      if table_name.respond_to?(:to_sym) &&
         (table_guard_skip_tables.include?(table_name.to_sym) ||
          table_guard_skip_tables.include?(table_name.to_s))
        return true
      end

      # Qualified names live outside the current search_path's unqualified
      # listing, so probe them directly (schema-aware) rather than matching the
      # Set. Rare path — the log noise this can produce does not hit boot.
      return db.table_exists?(table_name) if qualified_table_name?(table_name)

      existing_tables ||= existing_table_names
      existing_tables.include?(table_name.to_sym)
    rescue StandardError => e
      rodauth_warn("[table_guard] Unable to check table existence for #{table_name}: #{e.message}")
      true # Assume exists to avoid false positives (see hardening follow-up #116)
    end

    # List all required table names (sorted)
    #
    # @return [Array<String>] Sorted table names
    def list_all_required_tables
      table_configuration.values.map { |info| info[:name] }.uniq.sort
    end

    # Get detailed status for all tables
    #
    # @return [Array<Hash>] Status information for each table
    def table_status
      # Build the existing-name set once and reuse it (see missing_tables).
      existing = existing_table_names

      table_configuration.map do |method, info|
        {
          method: method,
          table: info[:name],
          feature: info[:feature],
          exists: table_exists?(info[:name], existing)
        }
      end
    end

    # Register a required column for validation and generation
    #
    # This method allows features like external_identity to register
    # column requirements that should be validated and optionally
    # created via ALTER TABLE statements.
    #
    # @param table_name [Symbol] Table name (e.g., :accounts)
    # @param column_def [Hash] Column definition with keys:
    #   - :name [Symbol] Column name (required)
    #   - :type [Symbol] Column type (default: :String)
    #   - :null [Boolean] Allow NULL (default: true)
    #   - :default [Object] Default value (optional)
    #   - :unique [Boolean] Unique constraint (default: false)
    #   - :size [Integer] Column size for strings (optional)
    #   - :index [Boolean, Hash] Create index (default: false)
    #   - :feature [Symbol] Feature that requires this column (default: :unknown)
    #
    # @example
    #   register_required_column(:accounts, {
    #     name: :stripe_customer_id,
    #     type: :String,
    #     null: true,
    #     unique: true,
    #     index: true,
    #     feature: :external_identity
    #   })
    def register_required_column(table_name, column_def)
      table_name = table_name.to_sym
      column_name = column_def[:name].to_sym

      # Initialize table entry if needed
      column_requirements[table_name] ||= {}

      # Store column definition with all Sequel options
      column_requirements[table_name][column_name] = {
        type: column_def[:type] || :String,
        null: column_def.fetch(:null, true),
        default: column_def[:default],
        unique: column_def[:unique],
        size: column_def[:size],
        index: column_def[:index],
        feature: column_def[:feature] || :unknown
      }

      rodauth_debug("[table_guard] Registered required column #{table_name}.#{column_name} (#{column_def[:feature]})")
    end

    # Get missing columns across all registered requirements
    #
    # @return [Array<Hash>] Array of missing column information
    def missing_columns
      result = []

      column_requirements.each do |table_name, columns|
        # Skip if table doesn't exist yet
        next unless table_exists?(table_name)

        # Get actual columns from database
        actual_columns = db.schema(table_name).map { |col| col[0] }

        # Check each required column
        columns.each do |column_name, column_def|
          next if actual_columns.include?(column_name)

          result << {
            table: table_name,
            column: column_name,
            type: column_def[:type],
            null: column_def[:null],
            default: column_def[:default],
            unique: column_def[:unique],
            size: column_def[:size],
            index: column_def[:index],
            feature: column_def[:feature]
          }
        end
      end

      result
    end

    # List all required columns
    #
    # @return [Array<Hash>] Array of column requirements
    def list_all_required_columns
      result = []

      column_requirements.each do |table_name, columns|
        columns.each do |column_name, column_def|
          result << {
            table: table_name,
            column: column_name,
            type: column_def[:type],
            null: column_def[:null],
            default: column_def[:default],
            unique: column_def[:unique],
            size: column_def[:size],
            index: column_def[:index],
            feature: column_def[:feature]
          }
        end
      end

      result.sort_by { |col| [col[:table].to_s, col[:column].to_s] }
    end

    # Get detailed status for all columns
    #
    # @return [Array<Hash>] Status information for each column
    def column_status
      result = []

      column_requirements.each do |table_name, columns|
        # Get actual columns if table exists
        actual_columns = if table_exists?(table_name)
                           db.schema(table_name).map { |col| col[0] }
                         else
                           []
                         end

        columns.each do |column_name, column_def|
          result << {
            table: table_name,
            column: column_name,
            type: column_def[:type],
            null: column_def[:null],
            default: column_def[:default],
            unique: column_def[:unique],
            size: column_def[:size],
            index: column_def[:index],
            feature: column_def[:feature],
            exists: actual_columns.include?(column_name),
            table_exists: table_exists?(table_name)
          }
        end
      end

      result
    end

    private

    # Build the set of unqualified table names that currently exist, including
    # views (which db.tables omits on most adapters but which can legitimately
    # back a Rodauth table).
    #
    # Fetched fresh on each call — never memoized on the instance — so runtime
    # introspection reflects tables created after boot. Looping callers pass the
    # result into #table_exists? to fetch it only once per pass (see #116 / N+1).
    #
    # @return [Set<Symbol>] Existing base-table and view names
    def existing_table_names
      names = db.tables.map(&:to_sym)
      names.concat(db.views.map(&:to_sym)) if db.respond_to?(:views)
      # Set.new (not names.to_set): referencing the Set constant triggers its
      # autoload on Ruby >= 3.2 (the gem's floor), whereas Enumerable#to_set is
      # only defined once 'set' is already loaded. Using to_set here would rely
      # on a dependency having required 'set' first and could otherwise raise
      # NoMethodError. This also keeps Lint/RedundantRequireStatement satisfied.
      Set.new(names)
    end

    # Determine whether a table identifier is schema-qualified.
    #
    # Qualified identifiers are not present in db.tables (which lists unqualified
    # names from the current search_path), so #table_exists? routes them to a
    # schema-aware probe instead of the Set match.
    #
    # Recognizes Sequel's qualified forms: a QualifiedIdentifier (from
    # Sequel.qualify) and the implicit-qualification Symbol form :schema__table.
    # A String with underscores is a literal name, not a qualification.
    #
    # @param table_name [Object] Table identifier
    # @return [Boolean] True if schema-qualified
    def qualified_table_name?(table_name)
      return true if defined?(Sequel::SQL::QualifiedIdentifier) &&
                     table_name.is_a?(Sequel::SQL::QualifiedIdentifier)

      table_name.is_a?(Symbol) && table_name.to_s.include?('__')
    end

    # Resolve table_guard_mode to its symbol value, or nil when it is a
    # block/Proc handler.
    #
    # A block handler (arity > 0) cannot be evaluated without arguments, and a
    # 0-arity Proc is a custom handler rather than a mode symbol; in both cases
    # there is no symbol to compare against, so we return nil. This lets callers
    # do `%i[raise halt exit].include?(table_guard_mode_symbol)` safely instead
    # of invoking table_guard_mode with the wrong arity.
    #
    # @return [Symbol, nil] the configured mode symbol, or nil for block/Proc handlers
    def table_guard_mode_symbol
      return nil if method(:table_guard_mode).arity > 0

      value = table_guard_mode
      value.is_a?(Proc) ? nil : value
    end

    # Handle column validation based on mode setting
    #
    # @param missing_cols [Array<Hash>] Missing column information
    def handle_column_guard_mode(missing_cols)
      return if missing_cols.empty?

      # Check if table_guard_mode is a block by inspecting method arity
      mode_method = method(:table_guard_mode)

      # If method expects parameters, it's a custom block handler
      if mode_method.arity > 0
        # Call with appropriate arguments based on arity
        result = case mode_method.arity
                 when 1 then table_guard_mode(missing_cols)
                 else table_guard_mode(missing_cols, column_requirements)
                 end

        case result
        when :error, :raise, true
          raise Rodauth::ConfigurationError, build_missing_columns_message(missing_cols)
        when String
          raise Rodauth::ConfigurationError, result
          # :continue, nil, false means don't raise
        end
        return
      end

      # Safe to call without arguments - get the mode value
      mode = table_guard_mode

      # If it's a 0-arity Proc, call it
      if mode.is_a?(Proc)
        result = mode.call

        case result
        when :error, :raise, true
          raise Rodauth::ConfigurationError, build_missing_columns_message(missing_cols)
        when String
          raise Rodauth::ConfigurationError, result
          # :continue, nil, false means don't raise
        end
        return
      end

      # Handle symbol modes
      case mode
      when :silent, :skip, nil
        rodauth_debug("[table_guard] Discovered #{list_all_required_columns.size} columns, skipping validation")

      when :warn
        rodauth_warn(build_missing_columns_message(missing_cols))

      when :error
        # Print distinctive message to error log but continue execution
        rodauth_error(build_missing_columns_error(missing_cols))

      when :raise
        # Let the error propagate up
        rodauth_error(build_missing_columns_error(missing_cols))
        raise Rodauth::ConfigurationError, build_missing_columns_message(missing_cols)

      when :halt, :exit
        # Exit the process early
        rodauth_error(build_missing_columns_error(missing_cols))
        exit(1)

      else
        raise Rodauth::ConfigurationError,
              "Invalid table_guard_mode: #{mode.inspect}. " \
              'Expected :silent, :skip, :warn, :error, :raise, :halt, or a Proc.'
      end
    end

    # Handle table validation based on mode setting
    #
    # @param missing [Array<Hash>] Missing table information
    def handle_table_guard_mode(missing)
      # Check if table_guard_mode is a block by inspecting method arity
      mode_method = method(:table_guard_mode)

      # If method expects parameters, it's a custom block handler
      if mode_method.arity > 0
        # Call with appropriate arguments based on arity
        result = case mode_method.arity
                 when 1 then table_guard_mode(missing)
                 else table_guard_mode(missing, table_configuration)
                 end

        case result
        when :error, :raise, true
          raise Rodauth::ConfigurationError, build_missing_tables_message(missing)
        when String
          raise Rodauth::ConfigurationError, result
          # :continue, nil, false means don't raise
        end
        return
      end

      # Safe to call without arguments - get the mode value
      mode = table_guard_mode

      # If it's a 0-arity Proc, call it
      if mode.is_a?(Proc)
        result = mode.call

        case result
        when :error, :raise, true
          raise Rodauth::ConfigurationError, build_missing_tables_message(missing)
        when String
          raise Rodauth::ConfigurationError, result
          # :continue, nil, false means don't raise
        end
        return
      end

      # Handle symbol modes
      case mode
      when :silent, :skip, nil
        rodauth_debug("[table_guard] Discovered #{@table_configuration.size} tables, skipping validation")

      when :warn
        rodauth_warn(build_missing_tables_message(missing))

      when :error
        # Print distinctive message to error log but continue execution
        rodauth_error(build_missing_tables_error(missing))

      when :raise
        # Let the error propagate up
        rodauth_error(build_missing_tables_error(missing))
        raise Rodauth::ConfigurationError, build_missing_tables_message(missing)

      when :halt, :exit
        # Exit the process early
        rodauth_error(build_missing_tables_error(missing))
        exit(1)

      else
        raise Rodauth::ConfigurationError,
              "Invalid table_guard_mode: #{mode.inspect}. " \
              'Expected :silent, :skip, :warn, :error, :raise, :halt, or a Proc.'
      end
    end

    # Handle Sequel generation based on sequel mode
    #
    # @param missing [Array<Hash>] Missing table information
    # @param missing_cols [Array<Hash>] Missing column information
    def handle_sequel_generation(missing, missing_cols = [])
      generator = Rodauth::SequelGenerator.new(missing, self, missing_cols)

      case table_guard_sequel_mode
      when :log
        rodauth_info("[table_guard] Sequel migration code:\n\n#{generator.generate_migration}")

      when :migration
        filename = generate_migration_filename
        FileUtils.mkdir_p(File.dirname(filename))
        File.write(filename, generator.generate_migration)
        rodauth_info("[table_guard] Generated migration file: #{filename}")

      when :create
        rodauth_debug("[table_guard] Creating #{missing.size} table(s)...")
        generator.execute_creates(db)
        rodauth_info("[table_guard] Created #{missing.size} table(s)")

        # Re-validate to show success message
        revalidate_after_creation

      when :sync
        unless %w[dev development test].any? { |env| ENV['RACK_ENV']&.start_with?(env) }
          rodauth_error("[table_guard] :sync mode only available in dev/test environments (current: #{ENV.fetch(
            "RACK_ENV", nil
          )})")
          return
        end

        # Drop and recreate only missing tables
        rodauth_info("[table_guard] Syncing #{missing.size} table(s)...")
        generator.execute_drops(db)
        generator.execute_creates(db)
        rodauth_info("[table_guard] Synced #{missing.size} table(s) (dropped and recreated)")

        # Re-validate to show success message
        revalidate_after_creation

      when :recreate
        unless %w[dev development test].any? { |env| ENV['RACK_ENV']&.start_with?(env) }
          rodauth_error("[table_guard] :recreate mode only available in dev/test environments (current: #{ENV.fetch(
            "RACK_ENV", nil
          )})")
          return
        end

        # Enumerate every table the enabled features' ERB templates create —
        # including "hidden" tables such as account_statuses and
        # account_password_hashes that have no *_table method (RT-09) — and drop
        # them in FK-dependency order via the generator (the same path :sync
        # already uses). The previous code dropped only the discovered *_table
        # names in reversed hash order, so it left the hidden tables in place and
        # the recreate step then failed with "table account_statuses already
        # exists", making :recreate unusable with the default schema.
        features = enabled_template_features

        rodauth_info("[table_guard] Recreating tables for #{features.size} feature(s) " \
                     '(dropping all, creating fresh)...')

        # Wrap the whole drop+create cycle in one transaction so a failure
        # part-way through cannot leave a partially dropped schema (RT-08).
        # Transactional DDL is a no-op on MySQL (it auto-commits DDL), but it
        # makes PostgreSQL and SQLite atomic, which is exactly where an
        # out-of-order drop would otherwise destroy data and then fail.
        db.transaction do
          generator.execute_drops(db, features: features)

          # Every required table is now missing, so recreate them all from the
          # templates (base.erb brings back the hidden tables too).
          current_missing = missing_tables
          current_missing_cols = missing_columns
          if current_missing.any? || current_missing_cols.any?
            generator_for_all = Rodauth::SequelGenerator.new(current_missing, self, current_missing_cols)
            generator_for_all.execute_creates(db)
          end
        end

        rodauth_info("[table_guard] Recreated tables for #{features.size} feature(s)")

        # Re-validate to show success message
        revalidate_after_creation

        # This is useful when you already have auto migrations that run at start
        # time. This will drop the tables so that the migrations run every time.
      when :drop
        unless %w[dev development test].any? { |env| ENV['RACK_ENV']&.start_with?(env) }
          rodauth_error("[table_guard] :drop mode only available in dev/test environments (current: #{ENV.fetch(
            "RACK_ENV", nil
          )})")
          return
        end

        # Drop every table the enabled features' templates create, hidden
        # tables included (RT-09), in FK-dependency order via the generator.
        features = enabled_template_features

        rodauth_info("[table_guard] Dropping tables for #{features.size} feature(s)...")

        # One transaction for the whole drop so it is atomic (RT-08).
        db.transaction do
          generator.execute_drops(db, features: features)

          # Drop Sequel migration tracking tables so migrations re-run from
          # scratch. These are independent leaf tables with no ordering
          # constraints, so the simple helper is fine; keeping them in the same
          # transaction makes the whole :drop atomic.
          drop_tables(%i[schema_info schema_migrations])
        end

        rodauth_info("[table_guard] Dropped tables for #{features.size} feature(s) and migration tracking")
        rodauth_info('[table_guard] Migrations will run from scratch on next execution')

      else
        rodauth_error("[table_guard] Invalid sequel mode: #{table_guard_sequel_mode.inspect}")
      end
    rescue StandardError => e
      rodauth_error("[table_guard] Sequel generation failed: #{e.class} - #{e.message}")
      rodauth_error("  Location: #{e.backtrace.first}")
      # Use the resolved symbol mode: calling table_guard_mode directly would
      # raise ArgumentError here when the user configured a block handler
      # (arity > 0), masking the real error `e` we are trying to surface.
      raise if %i[raise halt exit].include?(table_guard_mode_symbol)
    end

    # Check if the database supports CASCADE on DELETE
    #
    # @return [Boolean] True if using a db engine that supports DELETE ... CASCADE
    def cascade_supported?
      %i[postgres mysql].include?(db.database_type)
    end

    # Feature names (matching ERB template basenames) for every discovered
    # required table, de-duplicated.
    #
    # Used by :recreate/:drop to enumerate the full set of tables to drop from
    # the templates — including hidden tables like account_statuses — rather
    # than only the discovered *_table names. A feature whose template is
    # missing simply contributes no tables (TemplateInspector returns [] for
    # it), which is consistent with the create path, which likewise cannot
    # build a table it has no template for.
    #
    # @return [Array<Symbol>] Enabled feature names that own required tables
    def enabled_template_features
      table_configuration.map { |_, info| info[:feature] }.compact.uniq
    end

    # Drop a set of independent tables (no inter-table foreign keys), with
    # CASCADE where the adapter supports it.
    #
    # This helper does NOT order for foreign-key dependencies. The destructive
    # sequel modes route their FK-ordered drops through
    # SequelGenerator#execute_drops, which enumerates the templates (hidden
    # tables included) and drops child-before-parent. This helper is now used
    # only for the Sequel migration-tracking tables (:schema_info,
    # :schema_migrations) in :drop mode, which have no ordering constraints. It
    # opens no transaction of its own, so a caller can wrap it (together with
    # execute_drops) in a single transaction for atomicity (RT-08).
    #
    # SQLite doesn't support CASCADE on DROP TABLE, so we detect the database
    # type and avoid it there.
    #
    # @param table_names [Array<String, Symbol>] Independent tables to drop
    def drop_tables(table_names)
      table_names.each do |table_name|
        next unless db.table_exists?(table_name)

        # SQLite: simple drop without CASCADE
        # PostgreSQL, MySQL: use CASCADE for proper cleanup
        options = {
          cascade: cascade_supported?
        }
        db.drop_table(table_name, **options)

        rodauth_debug("[table_guard] Dropped #{table_name} (#{options})") if ENV['RODAUTH_DEBUG']
      end
    end

    # Re-validate tables after creation to show success message
    #
    # This runs the validation again after tables are created,
    # which will display the success message instead of leaving
    # the error/warning messages as the last output
    def revalidate_after_creation
      rodauth_info('') # Blank line for readability

      still_missing = missing_tables

      if still_missing.empty?
        rodauth_info('=' * 70)
        rodauth_info('✓ [table_guard] All required tables now exist')
        rodauth_info("  #{table_configuration.size} tables validated successfully")
        rodauth_info('=' * 70)
      else
        rodauth_error("[table_guard] Still missing #{still_missing.size} table(s) after creation!")
        still_missing.each do |info|
          rodauth_error("  - #{info[:table]} (#{info[:feature]})")
        end
      end
    end

    # Generate migration filename with timestamp
    #
    # @return [String] Full path to migration file
    def generate_migration_filename
      timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      filename = "#{timestamp}_create_rodauth_tables.rb"
      File.join(table_guard_migration_path, filename)
    end

    # Build user-friendly message for missing tables
    #
    # @param missing [Array<Hash>] Missing table information
    # @return [String] Formatted message
    def build_missing_tables_message(missing)
      lines = ['Rodauth [table_guard] Missing required database tables!']
      lines << ''

      missing.each do |info|
        lines << "  - Table: #{info[:table]} (feature: #{info[:feature]}, method: #{info[:method]})"
      end

      lines << ''
      lines << build_migration_hints(missing)

      lines.join("\n")
    end

    # Build distinctive error message for error-level logging
    #
    # @param missing [Array<Hash>] Missing table information
    # @return [String] Formatted error message
    def build_missing_tables_error(missing)
      table_list = missing.map { |i| i[:table] }.join(', ')
      "CRITICAL: Missing Rodauth tables - #{table_list}"
    end

    # Build helpful hints for resolving missing tables
    #
    # @param missing [Array<Hash>] Missing table information
    # @return [String] Formatted hints
    def build_migration_hints(missing)
      hints = []
      hints << ''
      hints << '⚠️  DATABASE OPERATIONS WILL FAIL UNTIL TABLES ARE CREATED'
      hints << ''

      unique_tables = missing.map { |i| i[:table] }.uniq

      if table_guard_sequel_mode.nil?
        hints << 'Quick fix for development (creates tables automatically):'
        hints << '  table_guard_sequel_mode :create'
        hints << ''
        hints << 'Other options:'
        hints << '  table_guard_sequel_mode :log        # Show migration code'
        hints << '  table_guard_sequel_mode :migration  # Generate migration file'
        hints << ''
      end

      hints << 'Required tables:'
      unique_tables.each do |table|
        hints << "  - #{table}"
      end

      hints << ''
      hints << 'To disable checking: table_guard_mode :silent'
      hints << "To skip specific tables: table_guard_skip_tables #{unique_tables.inspect}"

      hints.join("\n")
    end

    # Build user-friendly message for missing columns
    #
    # @param missing_cols [Array<Hash>] Missing column information
    # @return [String] Formatted message
    def build_missing_columns_message(missing_cols)
      lines = ['Rodauth [table_guard] Missing required database columns!']
      lines << ''

      # Group by table
      by_table = missing_cols.group_by { |col| col[:table] }
      by_table.each do |table, cols|
        lines << "  Table: #{table}"
        cols.each do |col|
          lines << "    - Column: #{col[:column]} (type: #{col[:type]}, feature: #{col[:feature]})"
        end
      end

      lines << ''
      lines << build_column_migration_hints(missing_cols)

      lines.join("\n")
    end

    # Build distinctive error message for columns
    #
    # @param missing_cols [Array<Hash>] Missing column information
    # @return [String] Formatted error message
    def build_missing_columns_error(missing_cols)
      column_list = missing_cols.map { |c| "#{c[:table]}.#{c[:column]}" }.join(', ')
      "CRITICAL: Missing Rodauth columns - #{column_list}"
    end

    # Build helpful hints for resolving missing columns
    #
    # @param missing_cols [Array<Hash>] Missing column information
    # @return [String] Formatted hints
    def build_column_migration_hints(missing_cols)
      hints = []
      hints << ''
      hints << '⚠️  DATABASE OPERATIONS MAY FAIL UNTIL COLUMNS ARE ADDED'
      hints << ''

      if table_guard_sequel_mode.nil?
        hints << 'Quick fix for development (adds columns automatically):'
        hints << '  table_guard_sequel_mode :create'
        hints << ''
        hints << 'Other options:'
        hints << '  table_guard_sequel_mode :log        # Show migration code'
        hints << '  table_guard_sequel_mode :migration  # Generate migration file'
        hints << ''
      end

      hints << 'Required columns:'
      missing_cols.each do |col|
        hints << "  - #{col[:table]}.#{col[:column]} (#{col[:type]}, #{col[:feature]})"
      end

      hints << ''
      hints << 'To disable checking: table_guard_mode :silent'

      hints.join("\n")
    end

    # Get logger instance with fallback chain
    #
    # Checks in order:
    # 1. table_guard_logger (feature-specific logger instance)
    # 2. SemanticLogger[table_guard_logger_name] (if name provided)
    # 3. logger (Rodauth instance method if defined by user)
    # 4. scope.logger (Roda app logger if available)
    # 5. nil (no logger available)
    #
    # For SemanticLogger integration, use table_guard_logger_name instead of
    # table_guard_logger to ensure level configuration is preserved:
    #
    #   table_guard_logger_name 'rodauth'  # Looks up SemanticLogger['rodauth']
    #
    # Note: SemanticLogger[] creates a new logger instance each time it's called.
    # If you configure logger levels via YAML or code, use table_guard_logger_name
    # so the feature can look up the logger at runtime and get the configured instance.
    def get_logger
      result = table_guard_logger

      # If no direct logger but name provided, look up SemanticLogger
      result = SemanticLogger[table_guard_logger_name] if !result && table_guard_logger_name && defined?(SemanticLogger)

      # Fallback chain if still no logger
      result ||= (respond_to?(:logger) ? logger : nil) ||
                 (respond_to?(:scope) && scope.respond_to?(:logger) ? scope.logger : nil)

      # Warn once if logger appears to be SemanticLogger but has no appenders
      if result && result.class.name&.include?('SemanticLogger') &&
         defined?(SemanticLogger) && SemanticLogger.appenders.empty?
        warn '[table_guard] WARNING: SemanticLogger has no appenders configured. ' \
             'Add: SemanticLogger.add_appender(io: STDOUT, level: :info)'
      end

      result
    end

    # Debug logging helper
    def rodauth_debug(msg)
      logger = get_logger
      return unless logger

      if logger.respond_to?(:debug)
        logger.debug(msg)
      elsif ENV['RODAUTH_DEBUG']
        warn "[DEBUG] #{msg}"
      end
    end

    # Info logging helper
    def rodauth_info(msg)
      logger = get_logger

      if logger&.respond_to?(:info)
        logger.info(msg)
      elsif logger&.respond_to?(:<<)
        # Support loggers that only have << method
        logger << "#{msg}\n"
      else
        puts msg
      end
    end

    # Warn logging helper
    def rodauth_warn(msg)
      logger = get_logger

      if logger&.respond_to?(:warn)
        logger.warn(msg)
      elsif logger&.respond_to?(:<<)
        logger << "[WARN] #{msg}\n"
      else
        warn msg
      end
    end

    # Error logging helper
    def rodauth_error(msg)
      logger = get_logger

      if logger&.respond_to?(:error)
        logger.error(msg)
      elsif logger&.respond_to?(:<<)
        logger << "[ERROR] #{msg}\n"
      else
        warn "[ERROR] #{msg}"
      end
    end
  end
end
