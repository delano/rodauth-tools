# Gemfile
#
# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'dry-inflector'
gem 'irb'
gem 'rake', '~> 13.4'

group :development do
  gem 'bundler-audit'
  gem 'rspec', '~> 3.0'
  gem 'rubocop', '~> 1.88'
  gem 'rubocop-rake'
  gem 'rubocop-rspec'
end

group :test do
  gem 'bcrypt', '~> 3.1'
  gem 'capybara'
  gem 'jwt', '~> 3.2'
  gem 'rack-test', '~> 2.1'
  gem 'rails', '>= 6.0'
  gem 'rotp'
  gem 'rqrcode'
  gem 'sequel-activerecord_connection', '~> 2.0'
  gem 'sqlite3', '~> 2.9'
  gem 'tilt', '~> 2.7'
  gem 'tryouts', '~> 3.0'
  gem 'warning'
  gem 'webauthn' unless RUBY_ENGINE == 'jruby'
end
