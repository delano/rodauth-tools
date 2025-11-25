# frozen_string_literal: true

# Rack configuration file for table_guard demo
#
# Run with:
#   bundle exec rackup
#
# Or with Puma:
#   bundle exec puma
#
# Visit: http://localhost:9292

require 'rack/session/cookie'

require_relative 'app'

use Rack::Session::Cookie,
    key: 'sinatra.session',
    secret: ENV.fetch('SESSION_SECRET',
                      '5c6281e7aceeca5b0b28ec2d732ba532c411b4e8127ff9ea6f383ece28011f8edc585bd1ebc30c4d3fcc5e78d89b1e0fbf8355d4d0f71d9ca8734b8b06510686'),
    same_site: :lax,
    httponly: true

# Run the Sinatra application
run TableGuardDemo
