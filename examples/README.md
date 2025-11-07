# Examples

## sinatra-table-guard

Barebones Sinatra app demonstrating the `table_guard` feature with dynamic table discovery and validation.

```bash
cd sinatra-table-guard
bundle install
bundle exec rackup        # Web server on http://localhost:9292
bundle exec ruby console.rb  # Interactive console
```

**What it demonstrates:**

- ✅ Validation modes (`:warn`, `:error`, `:raise`, `:halt`, custom block)
- ✅ Sequel generation modes (`:create`, `:log`, `:migration`, `:recreate`)
- ✅ Console introspection API (`missing_tables`, `table_status`, etc.)
- ✅ Environment-specific configuration patterns
- ✅ Integration with Sinatra/Roda middleware pattern

**What you'll learn:**

- How to catch missing tables at application startup
- Different validation strategies for development vs production
- Auto-creating tables for rapid development
- Generating migration files from table requirements
- Using introspection methods to debug table configuration

**Expected output:**

```
[10:30:45] WARN  Missing required database tables
[10:30:45] INFO  Creating 3 missing tables...
[10:30:45] INFO  ✓ Created table: accounts
[10:30:45] INFO  ✓ Created table: account_password_hashes
```

See [sinatra-table-guard/README.md](sinatra-table-guard/README.md) for full documentation.

## migration_logger_demo.rb

Simple script demonstrating logger suppression during Sequel table existence checks.

```bash
ruby examples/migration_logger_demo.rb
```

**What it demonstrates:**

- Why Sequel logs confusing errors when checking non-existent tables
- How table_guard suppresses these spurious error logs
- Before/after comparison of logger output

**Key insight:** When using `db.table_exists?(:nonexistent)`, Sequel attempts a SELECT query and logs the exception before catching it. The table_guard feature temporarily suppresses logging during these checks to keep your logs clean.
