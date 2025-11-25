# rodauth-tools.gemspec
#
# frozen_string_literal: true

require_relative 'lib/rodauth/tools/version'

Gem::Specification.new do |spec|
  spec.name = 'rodauth-tools'
  spec.version = Rodauth::Tools::VERSION
  spec.authors = ['delano']
  spec.summary = 'Framework-agnostic Rodauth tools'
  spec.description = <<~DESCRIPTION
    A collection of framework-agnostic tools and utilities for Rodauth, including
    database migration helpers, table inspection, and possibly... less (this is an
    active development area, experimental stuff that may come and go).
  DESCRIPTION
  spec.homepage = 'https://github.com/onetimesecret/rhales'
  spec.license = 'MIT'
  spec.metadata = {
    'bug_tracker_uri' => 'https://github.com/delano/rodauth-tools/issues',
    'changelog_uri' => 'https://github.com/delano/rodauth-tools/blob/main/CHANGELOG.md',
    'documentation_uri' => 'https://github.com/delano/rodauth-tools',
    'source_code_uri' => 'https://github.com/delano/rodauth-tools',
    'rubygems_mfa_required' => 'true',
  }
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ docs/ examples/ spec/ try/ .github])
    end
  end

  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.2.0'

  # Runtime dependencies only - needed by projects that use this via git
  spec.add_dependency 'dry-inflector', '~> 1.1'
  spec.add_dependency 'rodauth', '~> 2.41'
  spec.add_dependency 'sequel', '~> 5.0'
end
