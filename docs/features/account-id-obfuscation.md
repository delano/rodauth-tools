# Account ID Obfuscation Feature

Obfuscate the numeric `account_id` that Rodauth otherwise leaks in plaintext inside
email-verification links and the remember-me cookie — without changing your database
schema.

By default, a verification link looks like this, with the leading `2` being the
account's integer primary key:

```text
https://example.com/verify-account?key=2_SspVzDfIxrn3wzZ97lLQVZ6i9QO4VZkIaW2Wz0MU_s8
```

With this feature enabled it becomes:

```text
https://example.com/verify-account?key=A9F3K2M0QALZ7T_SspVzDfIxrn3wzZ97lLQVZ6i9QO4VZkIaW2Wz0MU_s8
```

The integer primary key is still used everywhere internally; only the value that
crosses the network is obfuscated.

## Installation

```ruby
enable :account_id_obfuscation
```

The feature depends on `email_base` (auto-enabled). It wraps the two email-token
chokepoints that all email-link features share, so a single `enable` covers
`verify_account`, `reset_password`, `email_auth`, `verify_login_change` and
`lockout`/`unlock`. When `remember` is also enabled, the remember-me cookie is
obfuscated too.

## How It Works

Rodauth email tokens are `<account_id><token_separator><random-or-HMAC-key>`. This
feature overrides two `email_base` methods:

- **`token_param_value`** (encode) — rewrites the `<account_id>` segment of the
  outgoing token to a version-tagged, obfuscated form.
- **`account_from_key`** (decode) — swaps the obfuscated segment back to the real
  integer before Rodauth's normal verification runs.

The obfuscated id is `<version><13 Crockford-Base32 chars>` (14 chars total), e.g.
`A9F3K2M0QALZ7T`. The `<version>` is a single **non-digit** character (`A` by
default). Because Rodauth's legacy ids are always decimal digits, the version tag
makes "is this obfuscated or a legacy id?" a deterministic first-character test —
which is what guarantees backward compatibility (see below).

The underlying transform is `Rodauth::Tools::AccountIdCipher`: a 4-round Feistel
network keyed with HMAC-SHA256 (keyed format-preserving encryption). It is a
bijection over the 64-bit domain, so every id maps to exactly one token and back,
with no collisions.

### Scoped overrides

This feature deliberately does **not** override the lower-level `split_token` /
`convert_token_id`, which are shared by other token consumers such as
`jwt_refresh`. By transforming only the id segment at the two email seams (and the
remember cookie), the blast radius is exactly the surfaces that leak `account_id`
in a user-visible URL or cookie. `internal_request` delegates through the override
untouched.

## Configuration

### `account_id_obfuscation_secret`

The obfuscation key. Must be at least 32 bytes. Leave unset to auto-load it from the
environment (see `account_id_obfuscation_secret_env_key`).

**Default:** `nil`

```ruby
account_id_obfuscation_secret ENV['ACCOUNT_ID_SECRET']
```

### `account_id_obfuscation_secret_env_key`

Environment variable name to read the secret from. The value is read **and deleted**
from `ENV` at configure time (same as `hmac_secret_guard`).

**Default:** `"ACCOUNT_ID_SECRET"`

```ruby
account_id_obfuscation_secret_env_key 'MY_ID_SECRET'
```

### `account_id_obfuscation_key_version`

Single, **non-digit** character prepended to each obfuscated token. Selects the
secret used to encode/decode and drives rotation. Must not be a digit, the
`token_separator`, or `_`.

**Default:** `'A'`

```ruby
account_id_obfuscation_key_version 'B'
```

### `account_id_obfuscation_previous_secrets`

Map of `{ version_char => old_secret }` consulted **only on decode**, to keep
tokens minted under a retired secret working during rotation. Defaults to empty, so
rotation is opt-in.

**Default:** `{}`

```ruby
account_id_obfuscation_previous_secrets({ 'A' => ENV['ACCOUNT_ID_SECRET_OLD'] })
```

### `account_id_obfuscation_remember_cookie?`

Whether to also obfuscate the remember-me cookie (only relevant when `remember` is
enabled).

**Default:** `true`

```ruby
account_id_obfuscation_remember_cookie? false
```

### `production_env_check`

Determines if the application is running in production (controls missing-secret
behaviour). Proc or Boolean.

**Default:** `proc { ENV.fetch('RACK_ENV', 'production') == 'production' }`

### `validate_secrets_on_configure?`

Enable/disable secret validation during the `post_configure` hook.

**Default:** `true`

### `development_account_id_obfuscation_secret_fallback`

Fallback secret (>= 32 bytes) used in development when none is configured.

**Default:** `'dev-only-insecure-account-id-obfuscation-secret-please-change-me'`

### Error / warning messages

- `account_id_obfuscation_secret_missing_error`
- `account_id_obfuscation_secret_too_short_error`
- `account_id_obfuscation_key_version_error`
- `account_id_obfuscation_secret_dev_warning`

## Usage

### Basic configuration

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :login, :verify_account, :remember
    enable :account_id_obfuscation
    # ACCOUNT_ID_SECRET is loaded from ENV and deleted after configure
  end
end
```

### Public methods

```ruby
rodauth.obfuscate_account_id(2)      # => "A9F3K2M0QALZ7T"
rodauth.deobfuscate_account_id(tok)  # => 2, or nil if tok is not one of our tokens
rodauth.production?                  # => true or false
rodauth.validate_secrets!            # manual secret validation
```

## Backward Compatibility

Rollout and rollback are safe with no schema or data migration:

- **In-flight email links.** A legacy link carries a decimal id segment
  (`2_abc...`). On decode, `deobfuscate_account_id('2')` returns `nil` (a legacy
  decimal has no version prefix), so the token passes through to Rodauth unchanged.
  Newly generated links carry `A9F3...`. Both work during and after rollout.
- **Legacy remember cookies.** Same rule: a numeric cookie id has no version prefix,
  so it is used as-is. Existing logged-in users are **not** forced to re-login.
- **Rollback.** Remove `enable :account_id_obfuscation`. New links/cookies revert to
  numeric; already-issued obfuscated links stop resolving (they need the feature to
  decode) but email links are short-lived, and obfuscated remember cookies simply
  degrade to a re-login.

The non-digit version tag is what makes this deterministic: without it, a legacy
13-digit decimal id would be indistinguishable from a 13-char obfuscated token. With
it, there is no ambiguity for ids of any size.

## Key Rotation

The secret is a reversible key: changing it re-maps every id. Rotate it on its own
schedule using version-keyed selection:

1. Generate a new secret and pick a new version char (e.g. `B`).
2. Move the current secret into `account_id_obfuscation_previous_secrets` under its
   old version char.

```ruby
plugin :rodauth do
  enable :account_id_obfuscation

  account_id_obfuscation_key_version 'B'
  account_id_obfuscation_secret ENV['ACCOUNT_ID_SECRET']            # new
  account_id_obfuscation_previous_secrets({ 'A' => ENV['ACCOUNT_ID_SECRET_OLD'] })
end
```

New tokens are minted under `B`; outstanding `A` tokens still decode. Drop the `A`
entry once those links/cookies have expired.

## Security Notes

**This is deterministic pseudonymisation, not access control or encryption of
confidential data.**

- The same id always maps to the same token, so tokens are **correlatable** — an
  observer can tell that two links reference the same account, they just can't tell
  *which* account.
- The obfuscation does **not** change a token's authority. The email-token HMAC (or
  random key) still gates the request after the id is swapped back to the real
  integer. Obfuscation is a privacy/anti-enumeration layer on top of authentication,
  never a replacement for it.
- Strength lives entirely in the **secret** (Kerckhoffs's principle): the design is
  public, and knowing it does not let an attacker reverse a token without the key.
- Use a dedicated `ACCOUNT_ID_SECRET`, independent of `hmac_secret`/`jwt_secret`, so
  rotating one does not invalidate the others' in-flight tokens. Generate at least 32
  bytes:

  ```bash
  openssl rand -base64 48
  # or
  ruby -r securerandom -e 'puts SecureRandom.hex(32)'
  ```

- Applies to **integer/bigint** primary keys. `Integer(id)` is used internally, so
  non-numeric (e.g. UUID) primary keys are out of scope.

## Standalone Cipher

`Rodauth::Tools::AccountIdCipher` is framework-agnostic and usable on its own:

```ruby
cipher = Rodauth::Tools::AccountIdCipher.new(ENV.fetch('ACCOUNT_ID_SECRET'))
cipher.encode(2)            # => "9F3K2M0QALZ7T"  (13 chars, no version tag)
cipher.decode('9F3K2M0QALZ7T')  # => 2
cipher.decode('not-a-token')    # => nil
```

The feature adds the version tag on top; the cipher itself is a pure
`Integer <-> 13-char` bijection.

## Testing

```ruby
RSpec.describe 'Account ID Obfuscation' do
  it 'obfuscates the id and round-trips it' do
    app = Class.new(Roda) do
      plugin :rodauth do
        db DB
        enable :login, :verify_account, :account_id_obfuscation
        hmac_secret 'h' * 32
        account_id_obfuscation_secret 'a' * 40
        production_env_check false
      end
      route(&:rodauth)
    end

    rodauth = app.rodauth.allocate
    token = rodauth.obfuscate_account_id(2)
    expect(token).to start_with('A')
    expect(rodauth.deobfuscate_account_id(token)).to eq(2)
    expect(rodauth.deobfuscate_account_id('2')).to be_nil # legacy id passes through
  end
end
```

Disable secret validation in tests that don't set a secret with
`validate_secrets_on_configure? false`.

## Related Features

- **email_base** - Provides the `token_param_value`/`account_from_key` chokepoints
  this feature wraps (dependency).
- **remember** - When enabled, its cookie is obfuscated too.
- **hmac_secret_guard** / **jwt_secret_guard** - Sibling secret-lifecycle features;
  this feature follows the same ENV-load-and-delete pattern.
- **jwt_refresh** - Unaffected: this feature never touches the global token split.

## References

- [Format-preserving encryption](https://en.wikipedia.org/wiki/Format-preserving_encryption)
- [Feistel cipher](https://en.wikipedia.org/wiki/Feistel_cipher)
- [Crockford Base32](https://www.crockford.com/base32.html)
- [Kerckhoffs's principle](https://en.wikipedia.org/wiki/Kerckhoffs%27s_principle)
