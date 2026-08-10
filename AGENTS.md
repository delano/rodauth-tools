# AGENTS.md

This file provides guidance to coding agents working in this repository.

## Project Purpose

Framework-agnostic utilities for Rodauth authentication:

1. **External Rodauth Features** - `table_guard` for database validation, `external_identity` for external service IDs, `hmac_secret_guard` for HMAC secret validation, `jwt_secret_guard` for JWT secret validation, `account_id_obfuscation` for hiding numeric account ids in email links and cookies
2. **Sequel Migration Generator** - Generate migrations for 19 Rodauth features

**Not a framework adapter.** For Rails integration, use rodauth-rails. This project demonstrates Rodauth's extensibility and provides reference implementations.

**Status:** Experimental. The gemspec says it plainly — "experimental stuff that may come and go" — so treat the API as unstable. It *is* published to RubyGems (`rodauth-tools`), and at least one production app depends on it, so a breaking change is a real cost to someone: bump the version and write the CHANGELOG entry.

**Namespace history (2025-10):** Namespace changed from `Rodauth::Rack::Generators::Migration` to `Rodauth::Tools::Migration`. This reflects the project's evolution away from being a Rack adapter toward being a collection of framework-agnostic utilities. The migration generator is now deprecated in favor of the `table_guard` feature with `sequel_mode`.

## Development Commands

```bash
# Run all tests
bundle exec rspec        # or: bundle exec rake

# Tryouts suite (documentation-style tests; auto-discovers try/, NOT run by CI)
bundle exec try

# Lint (config in .rubocop.yml, with .rubocop_todo.yml exclusions)
bundle exec rubocop lib/ spec/

# Interactive console with helpers
bin/console
```

## Architecture Overview

### Core Components

**lib/rodauth/features/table_guard.rb** - External Rodauth feature

- Uses `Rodauth::Feature.define(:table_guard, :TableGuard)` pattern
- Validates database tables exist for enabled features at `post_configure` time
- Provides introspection methods: `missing_tables`, `table_status`, `list_all_required_tables`
- Configurable modes: `:warn`, `:error`, `:silent`, or custom block handler
- Demonstrates proper feature lifecycle hooks and configuration DSL

**lib/rodauth/features/external_identity.rb** - External Rodauth feature

- Uses `Rodauth::Feature.define(:external_identity, :ExternalIdentity)` pattern
- Declares `accounts` columns holding IDs from external services (`external_identity_column :stripe_customer_id`) and generates a reader per column
- Layer 1 is the bare column plus conflict policy (`external_identity_on_conflict`: `:error`, `:warn`, `:skip`) and column presence checking (`external_identity_check_columns`: `true`, `false`, `:autocreate`)
- Layer 2 hangs lifecycle callables off the same declaration: `before_create_account`, `formatter`, `validator`, `verifier`, `handshake`
- Introspection: `external_identity_column_list`, `external_identity_column_config`, `external_identity_status`

**lib/rodauth/features/hmac_secret_guard.rb** - External Rodauth feature

- Uses `Rodauth::Feature.define(:hmac_secret_guard, :HmacSecretGuard)` pattern
- Automatically loads HMAC secret from environment variable (defaults to `HMAC_SECRET`)
- Validates secret is configured at application startup via `post_configure` hook
- Production mode: Raises `ConfigurationError` if secret missing, blank, or (when `minimum_secret_length` is set) too short
- Development mode: Logs warning and uses a fallback secret (random per-process by default)
- Deletes secret from ENV after loading for security (strips whitespace; blank values treated as absent)
- Provides `production?`, `validate_hmac_secret!`, and (aliased) `validate_secrets!` public methods

**lib/rodauth/features/jwt_secret_guard.rb** - External Rodauth feature

- Uses `Rodauth::Feature.define(:jwt_secret_guard, :JwtSecretGuard)` pattern
- Automatically loads JWT secret from environment variable (defaults to `JWT_SECRET`)
- Validates secret is configured at application startup via `post_configure` hook
- Production mode: Raises `ConfigurationError` if secret missing, blank, or (when `minimum_secret_length` is set) too short
- Development mode: Logs warning and uses a fallback secret (random per-process by default)
- Deletes secret from ENV after loading for security (strips whitespace; blank values treated as absent)
- Provides `production?`, `validate_jwt_secret!`, and (aliased) `validate_secrets!` public methods
- Defines `jwt_secret` configuration method for standalone use

**lib/rodauth/features/account_id_obfuscation.rb** - External Rodauth feature

- Uses `Rodauth::Feature.define(:account_id_obfuscation, :AccountIdObfuscation)` pattern
- Obfuscates `account_id` in email-link tokens and the remember cookie via scoped `token_param_value`/`account_from_key` (and conditional `_set_/_get_remember_cookie`) overrides
- Never touches the global `split_token`/`convert_token_id`, so `jwt_refresh` and other token consumers are unaffected
- Loads a dedicated `ACCOUNT_ID_SECRET` like the secret guards; `production?`/`validate_secrets!` lifecycle
- Non-digit version tag makes legacy-vs-obfuscated deterministic and drives config-driven secret rotation
- Delegates the crypto to the standalone `Rodauth::Tools::AccountIdCipher`

**lib/rodauth/tools/account_id_cipher.rb** - Framework-agnostic utility

- Keyed format-preserving obfuscation of a 64-bit integer id (4-round Feistel network, HMAC-SHA256 round function)
- Pure `Integer <-> 13-char Crockford Base32` bijection; stdlib `openssl` only, independently testable
- `decode` returns `nil` on malformed input so callers can pass legacy/foreign values through

**lib/rodauth/secret_guard.rb** - Shared support module (`Rodauth::SecretGuard`)

- Kind-parameterized (`:hmac`/`:jwt`) logic behind both secret-guard features
- Plain module functions taking the Rodauth instance explicitly — no mixed-in
  method names, so both guards can be enabled together without one shadowing the
  other (each feature's `post_configure` validates its own secret via `kind`)
- Handles ENV loading (`load_from_env!`), validation (`validate!`), blank/whitespace
  detection, production detection, and minimum-length enforcement

**lib/rodauth/table_inspector.rb** - Shared support module (`Rodauth::TableInspector`)

- Discovers the tables an enabled feature set requires by inspecting a live Rodauth instance, rather than from a static table
- `discover_tables(rodauth)` returns `{ accounts_table: "accounts", ... }`; `table_information(rodauth)` adds the owning feature and column list per table
- This is what backs `table_guard`'s `_table_configuration`, so it is the source of the `*_table` method enumeration described under Hidden Tables below

**lib/rodauth/tools/migration.rb** - Sequel migration generator

- Generates database migrations for 19 Rodauth features
- Uses ERB templates in `lib/rodauth/tools/migration/sequel/`
- Provides `generate()` for migration content and `migration_name()` for filename
- Uses dry-inflector gem for robust table name pluralization
- Mock database adapter pattern when no real DB connection provided
- Deprecated in favor of table_guard feature with sequel_mode

### How Rodauth Features Work

Rodauth features are modules that mix into `Rodauth::Auth` instances:

```ruby
Feature.define(:feature_name, :FeatureName) do
  # Configuration methods (overridable by users)
  auth_value_method :setting_name, 'default_value'

  # Public methods (overridable by users)
  auth_methods :public_method

  # Private methods (not overridable)
  auth_private_methods :internal_helper

  # Lifecycle hook - runs after configuration
  def post_configure
    super if defined?(super)
    # Initialization code
  end
end
```

**Key Pattern:** Methods defined in features become part of the Rodauth instance. Users override them in configuration blocks:

```ruby
plugin :rodauth do
  enable :feature_name

  setting_name 'custom_value'  # Override auth_value_method

  public_method do             # Override auth_methods
    # Custom implementation
  end
end
```

### Table Guard Implementation Details

**Existence Checks (no logger suppression):** The `table_exists?` method matches names against the database's table/view list (`db.tables` + `db.views`) rather than probing each table with a SELECT. An earlier implementation used Sequel's `table_exists?` probe and suppressed the logger around it (clearing/restoring the shared `db.loggers` array) to hide the "no such table" ERROR that Sequel logs before catching internally — but that mutation of shared connection state was not thread-safe. Listing names avoids the failed probe entirely, so no logger suppression (and no shared-state mutation) is needed. Schema-qualified identifiers (a `Sequel::SQL::QualifiedIdentifier` or a `:schema__table` Symbol) are not present in the unqualified list, so they take a separate schema-aware `db.table_exists?` probe path.

**Cached-Method Backing Visibility:** `auth_cached_method :foo` registers `foo` via `auth_private_methods`, so the backing `_foo` must be defined **private**. Rodauth 2.45.0 audits this at feature-definition time with `private_method_defined?` and warns (`RODAUTH3: raise instead of warn`) when it isn't — a publicly-defined `_foo` trips the audit even though it exists. `_table_configuration` and `_column_requirements` therefore live below the feature's `private` keyword, alongside the equivalent backing methods in `account_id_obfuscation` and `external_identity`.

`spec/rodauth/feature_configuration_spec.rb` holds the line. Two things about it are load-bearing, so preserve them when editing:

- It **derives** its feature list from `lib/rodauth/features/*.rb` and requires each file. A hardcoded list would leave a new feature silently uncovered — and the require is what makes the audit run at all, since rodauth audits inside `Feature.define` and never sees a feature nothing loaded.
- Per feature it **re-runs rodauth's own** `def_configuration_methods` with stderr captured and asserts silence, as well as mirroring what that method checks. The re-run cannot drift as upstream tightens the audit and honours `allowed_undefined_configuration_methods` (rodauth's opt-out) for free; the mirrored checks are what name the offending method when it fails.

**Configuration Storage:** Uses instance variables set by `auth_value_method`:

- Block configs stored as Procs in `@table_guard_mode`
- Symbol configs stored directly as `:warn`, `:error`, `:silent`

**Check Strategy:**

1. `should_check_tables?` examines `@table_guard_mode` to decide if checking is needed
2. Returns `true` if mode is a Proc (block), enabling custom handlers
3. Returns `true` if mode is `:warn` or `:error`, `false` for `:silent`

**Execution Flow:**

1. `post_configure` hook calls `check_required_tables!` if `should_check_tables?` returns true
2. `check_required_tables!` gets missing tables via `missing_tables`
3. For symbol modes (`:warn`, `:error`), handles directly
4. For block modes, calls block with missing tables, handles return value (`:error`, `:continue`, String)

**Introspection Methods:**

- `all_table_methods` - Finds all methods ending in `_table` using Ruby reflection
- `missing_tables` - Checks each required table against the existing table/view name set (fetched once per pass to avoid an N+1 of catalog queries)
- `table_status` - Returns array of hashes with method, table name, and existence status

### Migration Generator Architecture

**Note:** The Migration class is deprecated. For new code, use the `table_guard` feature with `sequel_mode` instead.

**Template System:**

- Each feature has ERB template in `lib/rodauth/tools/migration/sequel/`
- Templates use binding from Migration instance for variables like `table_prefix`
- `generate()` loads, evaluates, and concatenates all feature templates

**Pluralization:**

- Uses `dry-inflector` gem for intelligent pluralization (e.g., "status" → "statuses")
- Helper method `pluralize(str)` available in templates via ERB binding
- Removed Rails/ActiveRecord dependencies (68 lines of cruft eliminated)

**Database Adapter Pattern:**

- `MockSequelDatabase` simulates database when no real connection provided
- Allows template generation without active database
- Real `Sequel::Database` object can be passed for actual migrations
- Supports PostgreSQL, MySQL, and SQLite database types

### Hidden Tables Architecture

**Problem:** Some tables are created in ERB templates without corresponding `*_table` methods in Rodauth features.

**Example from base.erb:**

```ruby
# base.erb creates THREE tables:
create_table(:account_statuses)        # NO METHOD - Hidden!
create_table(:account_password_hashes) # NO METHOD - Hidden!
create_table(:accounts)                # Has accounts_table method ✓
```

**Why This Happens:**

- `account_statuses` - Lookup table for status values (Unverified=1, Verified=2, Closed=3). No method because users configure status IDs directly via `account_open_status_value`, etc.
- `account_password_hashes` - Separate table for security. Method is `account_password_hash_table` (singular), but ERB uses pluralized form based on `table_prefix`.

#### Solution: TemplateInspector Module

`lib/rodauth/template_inspector.rb` extracts table names directly from ERB templates by:

1. Creating minimal binding context with `table_prefix`, `pluralize`, and mock `db`
2. Evaluating ERB templates to render actual Ruby code
3. Parsing rendered code for `create_table()` calls using regex
4. Returning complete list of tables, including hidden ones

**Usage:**

```ruby
# Extract all tables for a feature
tables = TemplateInspector.extract_tables_from_template(
  :base,
  table_prefix: 'account'
)
# => [:account_statuses, :account_password_hashes, :accounts]

# Get tables for multiple features
all_tables = TemplateInspector.all_tables_for_features(
  [:base, :verify_account, :lockout],
  table_prefix: 'account'
)
```

**Impact on DROP Operations:**

Before TemplateInspector, `generate_drop_statements` only dropped dynamically discovered tables, missing hidden ones. Now it extracts the complete table list from ERB templates, ensuring all tables are properly dropped in correct dependency order.

**Key Insight:** ERB templates are the single source of truth for table schemas. By extracting information FROM templates instead of duplicating it in Ruby constants, we maintain consistency and eliminate hardcoded mappings.

## Testing Patterns

**RSpec Structure:**

- `spec/spec_helper.rb` - Minimal configuration; requires `rodauth/tools` and `rack/test`. It does **not** require `hmac_secret_guard` or `jwt_secret_guard` — those feature files are not loaded by `rodauth/tools`, so a spec that needs them must require them itself
- Feature specs test both behavior and configuration
- Migration generator specs verify template output and configuration
- `spec/rodauth/feature_configuration_spec.rb` - Guards every feature against rodauth's definition-time audit (see Cached-Method Backing Visibility above)

**Tryouts:** `try/features/*_try.rb` holds documentation-style tests, run separately from RSpec (`bundle exec try`). Only `external_identity` has one today. CI runs `bundle exec rake`, whose default task is `spec` alone — so **tryouts is not gated**, and it has drifted red: 5 of 50 fail as of 0.4.1. Don't read a red tryouts run as damage you just caused; check against the base branch first.

**Console Helpers:**

- `setup_test_db` - Creates in-memory SQLite database with tables
- `create_app(db, features: [...])` - Creates Roda app with Rodauth configured
- Useful for interactive testing of table_guard and migration generator

## Documentation Reference

**docs/rodauth-features-api.md** - Complete reference for feature development DSL methods

**docs/rodauth-integration.md** - Integrating Rodauth into a Rack app, and where this library fits

**docs/sequel-migrations.md** - Migration generator usage

**docs/rodauth-mail.md** - Email/SMTP configuration patterns

**docs/unresolved-bugs.md** - Known defects with analysis, not yet fixed. Read before "fixing" something surprising — it may already be written up here, with the reasoning for why it was left alone

**docs/features/** and **docs/examples/** - Per-feature documentation and runnable examples

Rodauth's own object model (`Rodauth::Auth`, `Rodauth::Configuration`, `Rodauth::Feature`, `Rodauth::FeatureConfiguration`) is documented upstream in `doc/guides/internals.rdoc` in the rodauth gem.

## Integration Pattern

Rodauth integrates with any Rack app via Roda middleware (NOT via this library):

```ruby
# Create Roda app with Rodauth
class RodauthApp < Roda
  plugin :middleware
  plugin :rodauth do
    enable :login, :logout
    enable :table_guard  # ← Feature from this library
    db DB
  end

  route do |r|
    r.rodauth
    env['rodauth'] = rodauth
  end
end

# Mount as Rack middleware
use RodauthApp
run MyApp
```

Access in your app: `request.env['rodauth']` provides all authentication methods.
