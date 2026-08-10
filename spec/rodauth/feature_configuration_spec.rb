# spec/rodauth/feature_configuration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'

# hmac_secret_guard/jwt_secret_guard are not auto-required by rodauth/tools.
require 'rodauth/features/hmac_secret_guard'
require 'rodauth/features/jwt_secret_guard'

# Every feature this gem defines, checked against rodauth's own audit below.
tools_features = %i[
  table_guard
  external_identity
  account_id_obfuscation
  hmac_secret_guard
  jwt_secret_guard
].freeze

# Rodauth 2.45.0 added a definition-time audit of every feature's configuration
# methods (Rodauth::FeatureConfiguration#_check_method_defined): a configuration
# method registered for a method the feature never defines means the
# configuration method silently does nothing. Today that emits
#
#   "Bug in Rodauth <feature> feature definition, configuration method added for
#    <meth>, but the feature doesn't define the method"
#
# on stderr at require time; upstream marks it "RODAUTH3: raise instead of warn",
# so a miss here becomes a load-time error in the next major release.
#
# These examples mirror that audit for the features this gem defines, so the
# breakage is caught here rather than as boot noise (eventually a boot failure)
# in a downstream app.
RSpec.describe Rodauth::FeatureConfiguration do
  tools_features.each do |feature_name|
    describe "#{feature_name} feature" do
      let(:feature) { Rodauth::FEATURES.fetch(feature_name) }

      it 'defines every method it registers a configuration method for' do
        registered = feature.auth_methods + feature.auth_value_methods
        undefined = registered.reject { |meth| feature.method_defined?(meth) || feature.private_method_defined?(meth) }

        expect(undefined).to be_empty,
                             "#{feature_name} registers configuration methods for #{undefined.join(", ")} " \
                             'but does not define them'
      end

      # auth_private_methods :foo (and auth_cached_method :foo, which calls it)
      # register a configuration method that redefines `_foo` PRIVATELY, so
      # rodauth checks the backing method with private_method_defined?. A
      # publicly-defined `_foo` fails that check even though it exists.
      it 'defines each auth_private_methods backing method privately' do
        backing = feature.auth_private_methods.map { |meth| :"_#{meth}" }
        not_private = backing.reject { |meth| feature.private_method_defined?(meth) }

        expect(not_private).to be_empty,
                               "#{feature_name} registers private configuration methods whose backing methods " \
                               "#{not_private.join(", ")} are missing or not private"
      end
    end
  end
end
