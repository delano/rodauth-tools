# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Replaced `# frozen_string_literal: true` with file path comments for better context
- Reordered features in README.md by common use case (table_guard first)
- Improved project status messaging and clarified this is a reference implementation
- Enhanced installation instructions with multiple options
- Updated documentation cross-references and fixed broken links
- Improved example documentation with expected output and learning outcomes

### Added
- Quick Start section to README.md showing immediate value
- CHANGELOG.md to track project changes
- Expected output examples in sinatra-table-guard documentation
- Detailed "What you'll learn" sections in examples

### Fixed
- Broken link from `docs/integration.md` to `docs/rodauth-integration.md`
- Missing context about project purpose and use cases

## [0.1.0] - 2025-10-15

### Added
- Table Guard feature for database table validation
- External Identity feature for tracking external service IDs
- HMAC Secret Guard feature for automatic secret validation
- JWT Secret Guard feature for automatic JWT secret validation
- Sequel migration generator for 19 Rodauth features
- Interactive console with helper methods
- Comprehensive test suite with RSpec
- Documentation for all features
- Sinatra example application

### Changed
- Namespace changed from `Rodauth::Rack::Generators::Migration` to `Rodauth::Tools::Migration`
- Evolution from Rack adapter to framework-agnostic utilities

[Unreleased]: https://github.com/delano/rodauth-tools/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/delano/rodauth-tools/releases/tag/v0.1.0
