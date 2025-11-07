# Sinatra table_guard Demo

Barebones Sinatra app demonstrating the `table_guard` feature with dynamic table discovery and validation.

## Quick Start

```bash
cd examples/sinatra-table-guard
bundle install
bundle exec rackup
# Visit: http://localhost:9292
```

Watch the console for table_guard logging!

## Interactive Console

```bash
bundle exec ruby console.rb
```

Helper methods:

- `config` - Get discovered table configuration
- `missing` - Get missing tables
- `show_status` - Pretty-print table status
- `create_tables!` - Create all missing tables
- `show_migration` - Display generated migration code

## Configuration Modes

Edit `app.rb` to try different modes:

```ruby
# Validation modes
table_guard_mode :warn       # Log warnings (default)
table_guard_mode :error      # Log errors
table_guard_mode :raise      # Raise exception
table_guard_mode :halt       # Exit process

# Sequel generation modes
table_guard_sequel_mode :log        # Log migration code
table_guard_sequel_mode :migration  # Generate file in db/migrate/
table_guard_sequel_mode :create     # Create tables immediately (JIT)
table_guard_sequel_mode :sync       # Drop and recreate (dev/test only)

# Custom handler
table_guard_mode do |missing, config|
  # Your logic here
  :continue
end
```

## What You'll See

### With `:warn` Mode (Default)

```
[10:30:45] WARN  Missing required database tables
[10:30:45] WARN  - accounts (feature: base, method: accounts_table)
[10:30:45] WARN  - account_password_hashes (feature: base, method: account_password_hashes_table)
[10:30:45] WARN  - account_verification_keys (feature: verify_account, method: verify_account_table)
[10:30:45] WARN
[10:30:45] WARN  💡 Migration hints:
[10:30:45] WARN    table_guard_sequel_mode :create     # Create tables now
[10:30:45] WARN    table_guard_sequel_mode :log        # Output migration code
[10:30:45] WARN    table_guard_sequel_mode :migration  # Generate migration file
```

### With `:create` Mode (Auto-create)

```
[10:30:45] WARN  Missing required database tables
[10:30:45] INFO  Creating 3 missing tables...
[10:30:45] INFO  ✓ Created table: accounts
[10:30:45] INFO  ✓ Created table: account_password_hashes
[10:30:45] INFO  ✓ Created table: account_verification_keys
[10:30:45] INFO  Successfully created all missing tables
```

### With `:raise` Mode (Production)

```
[10:30:45] ERROR CRITICAL: Missing Rodauth tables detected!
[10:30:45] ERROR - accounts (feature: base)
[10:30:45] ERROR - account_password_hashes (feature: base)
[10:30:45] ERROR
[10:30:45] ERROR This application cannot start without required database tables.
/path/to/app.rb:42:in `block': Missing required database tables! (Rodauth::ConfigurationError)
```

## Database

Default: SQLite (`db/sinatra_table_guard.db`)

PostgreSQL: `DATABASE_URL=postgres://localhost/rodauth_demo bundle exec rackup`

MySQL: `DATABASE_URL=mysql2://localhost/rodauth_demo bundle exec rackup`
