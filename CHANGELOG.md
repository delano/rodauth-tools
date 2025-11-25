# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-11-25

### Added

- **External Identity Layer 2 API** - Extended configuration options for external identity columns:
  - `before_create_account` callback for auto-generating IDs during account creation
  - `formatter` for normalizing values before storage
  - `validator` for validating values before storage
  - `verifier` for checking external service connectivity
  - `handshake` for OAuth state verification flows
- **TemplateInspector module** - Extracts table names directly from ERB templates to solve the "hidden tables" problem where templates create tables without corresponding `*_table` methods
- **SequelGenerator** - Generates Sequel migration code for missing Rodauth tables with:
  - ALTER TABLE support for adding missing columns
  - Integration with TemplateInspector for complete table discovery
  - Sequel column options support (types, constraints)
- **Table Guard column-level tracking** - Validates both tables AND columns exist for enabled features
- Comprehensive test coverage for new features

### Changed

- ERB templates now aligned with Rodauth README Sequel examples
- Removed hardcoded feature mappings from TableInspector in favor of dynamic discovery
- File headers standardized with path comments and `frozen_string_literal`

### Fixed

- DROP statement generation now uses TemplateInspector for complete table list
- `account_select` override behavior corrected for external identity columns
- Column type mapping for Class constants in migrations

## [0.2.0] - 2025-10-28

### Changed

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

[0.3.0]: https://github.com/delano/rodauth-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/delano/rodauth-tools/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/delano/rodauth-tools/releases/tag/v0.1.0
