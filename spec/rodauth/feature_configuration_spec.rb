# spec/rodauth/feature_configuration_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# Every feature this gem defines, derived from the filesystem rather than a
# hand-maintained list so a newly added feature is covered the moment its file
# lands. Each file defines exactly one feature whose name matches its basename.
#
# Requiring them here is also what makes the audit below run at all: rodauth
# audits a feature inside Feature.define, so a feature file nothing requires is
# never checked. rodauth/tools does not auto-require hmac_secret_guard or
# jwt_secret_guard, so the spec_helper require alone would miss them.
features_dir = File.expand_path('../../lib/rodauth/features', __dir__)
tools_features = Dir["#{features_dir}/*.rb"].map do |path|
  require path
  File.basename(path, '.rb').to_sym
end

# Guards the derivation itself: a glob that silently stopped matching would
# otherwise reduce this whole file to zero examples and still go green.
raise "no feature files found under #{features_dir}" if tools_features.empty?

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
# For each feature this gem defines, the examples below both re-run that audit
# and mirror what it checks, so the breakage is caught here rather than as boot
# noise (eventually a boot failure) in a downstream app.
RSpec.describe Rodauth::FeatureConfiguration do
  def capture_warnings
    old_stderr = $stderr
    $stderr = StringIO.new
    yield
    $stderr.string
  ensure
    $stderr = old_stderr
  end

  tools_features.each do |feature_name|
    describe "#{feature_name} feature" do
      let(:feature) { Rodauth::FEATURES.fetch(feature_name) }

      # A feature may opt individual methods out of the audit by setting
      # allowed_undefined_configuration_methods (2.45.0; nil unless the feature
      # assigns it — rodauth's json feature is the only upstream user). The two
      # mirrors below honour it so they cannot fail a feature that rodauth's own
      # audit deliberately permits.
      let(:allowed_undefined) { feature.allowed_undefined_configuration_methods || [] }

      # Runs rodauth's OWN audit rather than a copy of it, so this example
      # cannot drift as upstream tightens the check, and it honours
      # allowed_undefined_configuration_methods (2.45.0's opt-out, used by
      # rodauth's json feature for only_json?) for free. Re-running
      # def_configuration_methods is idempotent: it redefines the same
      # configuration methods on the same FeatureConfiguration module.
      #
      # The two examples below duplicate the checks it performs; they are kept
      # because upstream only emits a warning string, while they name the
      # offending methods and say which rule was broken.
      it "passes rodauth's own feature-definition audit" do
        warnings = capture_warnings { feature.configuration.def_configuration_methods(feature) }

        expect(warnings).to be_empty
      end

      it 'defines every method it registers a configuration method for' do
        registered = feature.auth_methods + feature.auth_value_methods
        undefined = registered.reject do |meth|
          feature.method_defined?(meth) || feature.private_method_defined?(meth) || allowed_undefined.include?(meth)
        end

        expect(undefined).to be_empty,
                             "#{feature_name} registers configuration methods for #{undefined.join(", ")} " \
                             'but does not define them'
      end

      # auth_private_methods :foo (and auth_cached_method :foo, which calls it)
      # register a configuration method that redefines `_foo` PRIVATELY, so
      # rodauth checks the backing method with private_method_defined?. A
      # publicly-defined `_foo` fails that check even though it exists.
      #
      # Upstream passes the ALREADY-prefixed name to its opt-out check, so an
      # opt-out here has to be spelled `:_foo`, not `:foo`. Accepting both would
      # make this mirror laxer than the audit it mirrors.
      it 'defines each auth_private_methods backing method privately' do
        backing = feature.auth_private_methods.map { |meth| :"_#{meth}" }
        not_private = backing.reject { |meth| feature.private_method_defined?(meth) || allowed_undefined.include?(meth) }

        expect(not_private).to be_empty,
                               "#{feature_name} registers private configuration methods whose backing methods " \
                               "#{not_private.join(", ")} are missing or not private"
      end
    end
  end
end
