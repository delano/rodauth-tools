# examples/sinatra-table-guard/app.rb
#
# frozen_string_literal: true

# Barebones Sinatra app demonstrating table_guard feature
#
# Run with:
#   ruby examples/sinatra-table-guard/app.rb
#
# Or load in console:
#   bin/console -r ./examples/sinatra-table-guard/app.rb

require "sinatra/base"
require "roda"
require "sequel"
require "logger"


# Add lib to load path so we can require our modules
$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)

require "rodauth/tools"

# Database setup
DB = Sequel.connect(
  ENV.fetch("DATABASE_URL", "sqlite://db/sinatra_table_guard.db")
)

# Configure logger
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::DEBUG
LOGGER.formatter = proc do |severity, datetime, _progname, msg|
  "[#{datetime.strftime('%H:%M:%S')}] #{severity.ljust(5)} #{msg}\n"
end

# Roda app for Rodauth middleware
class RodauthApp < Roda
  plugin :middleware
  plugin :render, views: File.expand_path("views", __dir__)
  plugin :flash

  plugin :rodauth do
    # Enable features for demonstration
    enable :login, :logout, :create_account, :verify_account
    enable :table_guard

    # Database
    db DB

    # Table guard configuration - try different modes!
    # Uncomment the mode you want to test:

    # Mode 1: Auto-create (development convenience)
    table_guard_mode :warn
    table_guard_sequel_mode :create  # Auto-create missing tables

    # PRODUCTION PATTERN: Use migrations as source of truth
    # if ENV['RACK_ENV'] == 'production'
    #   table_guard_mode :raise  # Fail if tables missing
    #   table_guard_sequel_mode nil  # Never auto-create
    # end

    # Mode 2: Error log but continue
    # table_guard_mode :error

    # Mode 3: Raise exception
    # table_guard_mode :raise

    # Mode 4: Log migration code
    # table_guard_mode :warn
    # table_guard_sequel_mode :log

    # Mode 5: Generate migration file
    # table_guard_mode :warn
    # table_guard_sequel_mode :migration

    # Mode 6: Create tables automatically (JIT - useful for dev)
    # table_guard_mode :warn
    # table_guard_sequel_mode :create

    # Mode 7: Drop and recreate ALL tables every startup (dev/test only - fresh start)
    # table_guard_mode :warn
    # table_guard_sequel_mode :recreate

    # Mode 8: Custom handler
    # table_guard_mode do |missing, config|
    #   puts "\n=== CUSTOM HANDLER ==="
    #   puts "Missing #{missing.size} tables:"
    #   missing.each do |info|
    #     puts "  - #{info[:table]} (feature: #{info[:feature]})"
    #   end
    #   puts "Total config entries: #{config.size}"
    #   puts "======================\n"
    #   :continue # Don't raise
    # end

    # Logging - application developers can use either approach:
    # Option 1: Standard Rodauth logger method (recommended - used by other features too)
    def logger
      LOGGER
    end

    # Option 2: Feature-specific logger (if you need different logger just for table_guard)
    # table_guard_logger LOGGER

    # Configuration
    accounts_table :accounts
    login_redirect "/"
    logout_redirect "/"
    require_login_confirmation? false
    require_password_confirmation? false
  end

  route do |r|
    r.rodauth

    # Make rodauth available to main app
    env["rodauth"] = rodauth
  end
end

# Main Sinatra application
class TableGuardDemo < Sinatra::Base
  configure do
    use RodauthApp
    set :logger, LOGGER
  end

  helpers do
    def rodauth
      request.env["rodauth"]
    end
  end

  get "/" do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Rodauth table_guard Demo</title>
        <style>
          body { font-family: sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
          h1 { color: #333; }
          .info { background: #e7f3ff; padding: 15px; border-radius: 5px; margin: 20px 0; }
          .status { background: #f0f0f0; padding: 15px; border-radius: 5px; margin: 20px 0; }
          pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
          .logged-in { color: green; }
          .logged-out { color: orange; }
          a { color: #0066cc; text-decoration: none; margin: 0 10px; }
          a:hover { text-decoration: underline; }
        </style>
      </head>
      <body>
        <h1>Rodauth table_guard Demo</h1>

        <div class="info">
          <h2>📊 Table Configuration Status</h2>
          <p>This demo shows the <code>table_guard</code> feature in action.</p>
          <p>Check the console output to see table validation logging!</p>
        </div>

        <div class="status">
          <h3>Database: #{DB.adapter_scheme}</h3>
          <h3>Authentication Status:
            <span class="#{rodauth.logged_in? ? 'logged-in' : 'logged-out'}">
              #{rodauth.logged_in? ? 'Logged In' : 'Not Logged In'}
            </span>
          </h3>

          #{if rodauth.logged_in?
              "<p>User ID: #{rodauth.account_id}</p>"
            end}
        </div>

        <div>
          <h3>Navigation</h3>
          #{if rodauth.logged_in?
              '<a href="/logout">Logout</a>'
            else
              '<a href="/login">Login</a> | <a href="/create-account">Create Account</a>'
            end}
        </div>

        <div class="info">
          <h3>🔍 Console Inspection</h3>
          <p>Load this app in <code>bin/console</code> to interrogate the configuration:</p>
          <pre>$ bin/console -r ./examples/sinatra-table-guard/app.rb

# Get table configuration
rodauth = RodauthApp.rodauth.allocate
rodauth.send(:initialize, {})
config = rodauth.table_configuration

# Check missing tables
missing = rodauth.missing_tables

# List all required tables
tables = rodauth.list_all_required_tables

# Get detailed status
status = rodauth.table_status</pre>
        </div>

        <div class="info">
          <h3>⚙️ Try Different Modes</h3>
          <p>Edit <code>examples/sinatra-table-guard/app.rb</code> to uncomment different <code>table_guard_mode</code> settings:</p>
          <ul>
            <li><strong>:warn</strong> - Log warnings but continue</li>
            <li><strong>:error</strong> - Log errors but continue</li>
            <li><strong>:raise</strong> - Raise exception (app won't start)</li>
            <li><strong>:log</strong> (sequel_mode) - Show migration code in logs</li>
            <li><strong>:migration</strong> (sequel_mode) - Generate migration file</li>
            <li><strong>:create</strong> (sequel_mode) - Create tables automatically</li>
            <li><strong>Block</strong> - Custom handling logic</li>
          </ul>
        </div>
      </body>
      </html>
    HTML
  end

  # Error handler to show table guard exceptions nicely
  error Rodauth::ConfigurationError do
    status 500
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>Configuration Error</title>
        <style>
          body { font-family: monospace; max-width: 900px; margin: 50px auto; padding: 20px; }
          .error { background: #ffebee; padding: 20px; border-left: 4px solid #c62828; }
          pre { white-space: pre-wrap; }
        </style>
      </head>
      <body>
        <h1>⚠️ Rodauth Configuration Error</h1>
        <div class="error">
          <pre>#{env['sinatra.error'].message}</pre>
        </div>
        <p>This is expected when <code>table_guard_mode :raise</code> is set and tables are missing.</p>
        <p>Check the console output for details.</p>
      </body>
      </html>
    HTML
  end
end

# Start the server when run directly
if __FILE__ == $PROGRAM_NAME
  puts "\n" + "=" * 70
  puts "🚀 Starting Rodauth table_guard Demo"
  puts "=" * 70
  puts "\nDatabase: #{DB.adapter_scheme}"
  puts "URL: http://localhost:4567"
  puts "\nWatch the console for table_guard logging output!"
  puts "=" * 70 + "\n\n"

  TableGuardDemo.run!
end
