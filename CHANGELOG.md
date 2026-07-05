# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-07-05

### Added

- **Account ID Obfuscation feature** (`account_id_obfuscation`) - Keyed, reversible
  obfuscation of the numeric `account_id` that leaks into email-link tokens (e.g.
  `/verify-account?key=2_...`) and the remember-me cookie, with no database schema
  change. Wraps the two `email_base` chokepoints (`token_param_value` /
  `account_from_key`), so a single `enable` covers verify_account, reset_password,
  email_auth, verify_login_change and lockout/unlock; also obfuscates the remember
  cookie when `remember` is enabled. Loads a dedicated `ACCOUNT_ID_SECRET` following
  the `hmac_secret_guard` pattern. Backward compatible with in-flight numeric links
  and legacy cookies, with config-driven secret rotation via a version tag.
- **`Rodauth::Tools::AccountIdCipher`** - Framework-agnostic 4-round Feistel
  format-preserving encryption utility (stdlib `openssl` only, no new dependencies).

## [0.3.1] - 2026-01-13

### Changed

- Dependency and development-tooling maintenance (bundled `rodauth`, `sequel`,
  `rubocop`, and related updates).

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

[0.4.0]: https://github.com/delano/rodauth-tools/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/delano/rodauth-tools/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/delano/rodauth-tools/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/delano/rodauth-tools/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/delano/rodauth-tools/releases/tag/v0.1.0
