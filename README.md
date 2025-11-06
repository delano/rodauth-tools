# Rodauth::Tools

Framework-agnostic utilities for [Rodauth](http://rodauth.jeremyevans.net) authentication. Provides external Rodauth features and Sequel migration generators.

> [!WARNING]
> This project is in early alpha. APIs may change significantly. Not ready for prime time.

## Overview

Rodauth::Tools provides utilities that work with any Rodauth setup, regardless of framework:

1. **External Rodauth Features** - Like `table_guard` for validating database table setup
2. **Sequel Migration Generator** - Generate Rodauth database migrations for 19 features

This is NOT a framework adapter. For framework integration, use:

- Rails: [rodauth-rails](https://github.com/janko/rodauth-rails)
- Others: Integrate Rodauth directly - [see integration guide](docs/integration.md)

## Installation

Clone this repository:

```bash
git clone https://github.com/delano/rodauth-tools
cd rodauth-tools
bundle install
```

## Features

### 1. HMAC Secret Guard Feature

Automatically configure and validate HMAC secrets at application startup to prevent deployment errors.

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :hmac_secret_guard

    # Production: Raises error if HMAC_SECRET missing
    # Development: Uses fallback secret with warning
  end
end
```

**Key Features:**

- Automatic loading from `HMAC_SECRET` environment variable
- Production mode: Raises `ConfigurationError` if secret missing
- Development mode: Logs warning and uses fallback
- Deletes secret from ENV after loading (security)
- Configurable production detection and error messages
- Public methods: `production?`, `validate_secrets!`

**Configuration Options:**

- `hmac_secret_env_key` - Environment variable name (default: `'HMAC_SECRET'`)
- `production_env_check` - Proc or boolean for production detection
- `validate_secrets_on_configure?` - Enable/disable validation (default: `true`)
- `development_hmac_secret_fallback` - Fallback secret for development
- `hmac_secret_missing_error` - Error message for production
- `hmac_secret_dev_warning` - Warning message for development

**Documentation:** [docs/features/hmac-secret-guard.md](docs/features/hmac-secret-guard.md)

### 2. JWT Secret Guard Feature

Automatically configure and validate JWT secrets at application startup to prevent deployment errors.

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :jwt_secret_guard

    # Production: Raises error if JWT_SECRET missing
    # Development: Uses fallback secret with warning
  end
end
```

**Key Features:**

- Automatic loading from `JWT_SECRET` environment variable
- Production mode: Raises `ConfigurationError` if secret missing
- Development mode: Logs warning and uses fallback
- Deletes secret from ENV after loading (security)
- Configurable production detection and error messages
- Public methods: `production?`, `validate_secrets!`
- Defines `jwt_secret` method for standalone use (no JWT feature required)

**Configuration Options:**

- `jwt_secret_env_key` - Environment variable name (default: `'JWT_SECRET'`)
- `production_env_check` - Proc or boolean for production detection
- `validate_secrets_on_configure?` - Enable/disable validation (default: `true`)
- `development_jwt_secret_fallback` - Fallback secret for development
- `jwt_secret_missing_error` - Error message for production
- `jwt_secret_dev_warning` - Warning message for development

**Documentation:** [docs/features/jwt-secret-guard.md](docs/features/jwt-secret-guard.md)

### 3. External Identity Feature

Store external service identifiers in your accounts table with automatic helper methods.

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :external_identity

    # Declare columns (names used as-is)
    external_identity_column :stripe_customer_id
    external_identity_column :redis_uuid
    external_identity_column :elasticsearch_doc_id

    # Configuration
    external_identity_check_columns :autocreate  # Generate migration code
  end
end

# Usage - helper methods match column names
rodauth.stripe_customer_id   # => "cus_abc123"
rodauth.redis_uuid           # => "550e8400-e29b-41d4-..."
rodauth.elasticsearch_doc_id # => "doc_789xyz"
```

**Key Features:**

- Declarative column configuration
- Automatic helper method generation
- Auto-inclusion in `account_select`
- Column existence validation with migration code generation
- Introspection API for debugging

**Common Use Cases:**

- Payment integration (Stripe customer IDs)
- Session management (Redis keys)
- Search indexing (Elasticsearch document IDs)
- Federated authentication (Auth0 user IDs)

**Documentation:** [docs/features/external-identity.md](docs/features/external-identity.md)

### 4. Table Guard External Feature

Validates that required database tables exist for enabled Rodauth features.

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :login, :logout, :otp
    enable :table_guard  # ← Add this

    table_guard_mode :raise  # or :warn, :error, :halt, :silent
  end
end
```

**Modes:**

- `:silent` / `:skip` / `nil` - Disable validation (debug log only)
- `:warn` - Log warning message and continue execution
- `:error` - Print distinctive message to error log but continue execution
- `:raise` - Log error and raise `Rodauth::ConfigurationError` (recommended for production)
- `:halt` / `:exit` - Log error and exit the process immediately
- Block - Custom handler (see below)

**Custom Handlers:**

```ruby
table_guard_mode do |missing|
  if Rails.env.production?
    Slack.notify("Missing tables: #{missing.map { |t| t[:table] }.join(', ')}")
    :raise  # Raise error
  else
    :continue  # Just log and continue
  end
end
```

**Introspection:**

```ruby
rodauth = MyApp.rodauth

# List all required tables
rodauth.list_all_required_tables
# => [:accounts, :account_password_hashes, :account_otp_keys, ...]

# Check status of each table
rodauth.table_status
# => [{method: :accounts_table, table: :accounts, exists: true}, ...]

# Get missing tables
rodauth.missing_tables
# => [{method: :otp_keys_table, table: :account_otp_keys}, ...]
```

### 5. Sequel Migration Generator

Generate database migrations for Rodauth features.

```ruby
require "rodauth/tools"

generator = Rodauth::Tools::Migration.new(
  features: [:base, :verify_account, :otp],
  prefix: "account"  # table prefix (default: "account")
)

# Get migration content
puts generator.generate

# Get Rodauth configuration
puts generator.configuration
# => {
#   accounts_table: :accounts,
#   verify_account_table: :account_verification_keys,
#   otp_keys_table: :account_otp_keys
# }
```

**Supported Features** (19 total):

- `base` - Core accounts table
- `remember` - Remember me functionality
- `verify_account` - Account verification
- `verify_login_change` - Login change verification
- `reset_password` - Password reset
- `email_auth` - Passwordless email authentication
- `otp` - TOTP multifactor authentication
- `otp_unlock` - OTP unlock
- `sms_codes` - SMS codes
- `recovery_codes` - Backup recovery codes
- `webauthn` - WebAuthn keys
- `lockout` - Account lockouts
- `active_sessions` - Session management
- `account_expiration` - Account expiration
- `password_expiration` - Password expiration
- `single_session` - Single session per account
- `audit_logging` - Authentication audit logs
- `disallow_password_reuse` - Password history
- `jwt_refresh` - JWT refresh tokens

## Console

Interactive console for testing:

```bash
bin/console
```

Example session:

```ruby
db = setup_test_db
app = create_app(db, features: [:login, :otp])
rodauth = app.rodauth

rodauth.list_all_required_tables
rodauth.table_status
rodauth.missing_tables
```

## Development

```bash
# Run tests
bundle exec rspec

# Run console
bin/console
```

## Architecture

**What this project is:**

- Collection of framework-agnostic Rodauth utilities
- External Rodauth features (using `Rodauth::Feature.define`)
- Migration generators for Sequel ORM

**What this project is NOT:**

- A framework adapter (use rodauth-rails for Rails)
- A replacement for Rodauth itself
- Published as a gem (it's a learning/reference project)

## Documentation

- **[HMAC Secret Guard Feature](docs/features/hmac-secret-guard.md)** - Validate HMAC secrets at startup
- **[JWT Secret Guard Feature](docs/features/jwt-secret-guard.md)** - Validate JWT secrets at startup
- **[External Identity Feature](docs/features/external-identity.md)** - Track external service identifiers
- **[Table Guard Feature](docs/features/table-guard.md)** - Validate required database tables
- **[Sequel Migrations](docs/sequel-migrations.md)** - Integrating table_guard with Sequel migrations
- **[Rodauth Feature API](docs/rodauth-features-api.md)** - Complete DSL reference for feature development
- **[Rodauth Internals](docs/references/rodauth-internals.rdoc)** - Object model and metaprogramming patterns
- **[Mail Configuration](docs/rodauth-mail.md)** - Email and SMTP setup

## Related Projects

- [rodauth](https://github.com/jeremyevans/rodauth) - The authentication framework
- [rodauth-rails](https://github.com/janko/rodauth-rails) - Rails integration
- [roda](https://github.com/jeremyevans/roda) - Routing tree web toolkit

## Acknowledgments

- **Migration Templates**: Copied from [rodauth-rails](https://github.com/janko/rodauth-rails) by Janko Marohnić
- **Inspiration**: rodauth-rails' excellent Rails integration

## License

MIT License
