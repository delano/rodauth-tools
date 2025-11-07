# lib/rodauth/tools.rb

# Rodauth must be loaded before our external features can be defined
begin
  require "rodauth"
rescue LoadError
  # Rodauth not available - external features won't be loaded
end

require_relative "tools/version"
require_relative "tools/migration"
require_relative "tools/console_helpers"

# Load rodauth-tools utilities (only if Rodauth is available)
if defined?(Rodauth)
  require_relative "table_inspector"
  require_relative "sequel_generator"
  require_relative "features/table_guard"
  require_relative "features/external_identity"
end

module Rodauth
  # Tools module contains framework-agnostic Rodauth utilities
  module Tools
    class Error < StandardError; end
  end
end
