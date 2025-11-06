# HMAC Secret Guard Feature

Automatically configure and validate HMAC secret at application startup to prevent deployment errors where secret environment variables might not be set correctly.

## Installation

```ruby
enable :hmac_secret_guard
```

## Configuration

### `hmac_secret_env_key`

Environment variable name to read HMAC secret from.

**Default:** `"HMAC_SECRET"`

```ruby
hmac_secret_env_key 'MY_HMAC_SECRET'
```

### `production_env_check`

Determines if application is running in production mode.

**Values:** Proc (dynamic check) or Boolean (static value)

**Default:** `proc { ENV.fetch('RACK_ENV', 'production') == 'production' }`

```ruby
# Proc - dynamic check
production_env_check proc { ENV['RACK_ENV'] == 'production' }

# Boolean - static value
production_env_check true

# Custom logic
production_env_check proc {
  ENV['RAILS_ENV'] == 'production' || ENV['DEPLOYMENT_ENV'] == 'staging'
}
```

### `validate_secrets_on_configure?`

Enable/disable secret validation during post_configure hook.

**Default:** `true`

```ruby
validate_secrets_on_configure? false  # Disable validation
```

### `development_hmac_secret_fallback`

Fallback HMAC secret for development environments.

**Default:** `'dev-only-insecure-example-hmac-secret-needs-to-be-changed-in-prod'`

```ruby
development_hmac_secret_fallback 'my-custom-dev-secret-12345'
```

### `hmac_secret_missing_error`

Error message when HMAC secret is missing in production.

**Default:** `"HMAC_SECRET environment variable must be set in production"`

```ruby
hmac_secret_missing_error 'CRITICAL: HMAC secret not configured!'
```

### `hmac_secret_dev_warning`

Warning message when using development fallback secret.

**Default:** `"[rodauth] WARNING: Using default HMAC secret for development only"`

```ruby
hmac_secret_dev_warning 'DEV WARNING: Using insecure HMAC secret'
```

## Usage

### Basic Configuration

```ruby
class RodauthApp < Roda
  plugin :rodauth do
    enable :hmac_secret_guard

    # Secret automatically loaded from HMAC_SECRET environment variable
  end
end
```

### Environment-Specific Configuration

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  case ENV['RACK_ENV']
  when 'production'
    production_env_check true
    # Raises error if HMAC_SECRET not set
  when 'development'
    production_env_check false
    # Uses development fallback
  when 'test'
    validate_secrets_on_configure? false
    # Skips validation in tests
  end
end
```

### Custom Environment Variable

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  hmac_secret_env_key 'MY_APP_HMAC_SECRET'
end
```

### Custom Production Detection

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  # Check multiple environments
  production_env_check proc {
    ['production', 'staging'].include?(ENV['RAILS_ENV'])
  }
end
```

### Disable Validation

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  validate_secrets_on_configure? false
end
```

## Behavior

### Auto-Configuration Flow

1. **Check existing hmac_secret**
   - If already set via configuration block, skip auto-configuration
   - If nil or empty, proceed to step 2

2. **Read from environment variable**
   - Read value from `HMAC_SECRET` (or configured env key)
   - Delete from ENV to prevent exposure
   - Set as hmac_secret method if value present

3. **Validate secrets**
   - Check if hmac_secret is properly configured
   - Production: Raise error if missing
   - Development: Warn and use fallback

### Production Mode

When `production?` returns true:

```ruby
# Missing HMAC_SECRET environment variable
# => Rodauth::ConfigurationError: HMAC_SECRET environment variable must be set in production
```

Application startup fails fast, preventing deployment with missing secrets.

### Development Mode

When `production?` returns false:

```ruby
# Missing HMAC_SECRET environment variable
# => [rodauth] WARNING: Using default HMAC secret for development only
# Application continues with development fallback
```

Logs warning to logger (if available) or stderr, then uses `development_hmac_secret_fallback`.

## Public Methods

### `validate_secrets!`

Manually trigger secret validation.

```ruby
rodauth.validate_secrets!
# Raises error in production if secret missing
# Sets fallback in development if secret missing
```

### `production?`

Check if running in production mode.

```ruby
rodauth.production?  # => true or false
```

## Security Best Practices

### 1. Use Environment Variables

Store secrets in environment variables, never in code:

```bash
# .env (development)
HMAC_SECRET=dev-secret-not-for-production

# Production deployment
export HMAC_SECRET=$(openssl rand -hex 64)
```

### 2. Validate in Production

Always enable validation in production:

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  if ENV['RACK_ENV'] == 'production'
    production_env_check true
  end
end
```

### 3. Use Strong Secrets

Generate cryptographically secure secrets:

```bash
# Generate 64-byte (512-bit) secret
openssl rand -hex 64

# Or using Ruby
ruby -r securerandom -e 'puts SecureRandom.hex(64)'
```

### 4. Rotate Secrets Regularly

Implement secret rotation for long-running applications:

```ruby
# Support both old and new secrets during rotation
hmac_secret ENV['HMAC_SECRET_NEW'] || ENV['HMAC_SECRET']
```

### 5. Never Commit Secrets

Add to `.gitignore`:

```gitignore
.env
.env.local
.env.production
*.secret
config/secrets.yml
```

## Integration Patterns

### With Docker

```dockerfile
# Dockerfile
ENV HMAC_SECRET=""

# docker-compose.yml
services:
  app:
    environment:
      - HMAC_SECRET=${HMAC_SECRET}
```

Run with:

```bash
docker-compose run -e HMAC_SECRET=$(openssl rand -hex 64) app
```

### With Kubernetes

```yaml
# secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: rodauth-secrets
type: Opaque
data:
  hmac-secret: <base64-encoded-secret>

# deployment.yaml
env:
  - name: HMAC_SECRET
    valueFrom:
      secretKeyRef:
        name: rodauth-secrets
        key: hmac-secret
```

### With Rails Credentials

```ruby
# config/credentials.yml.enc
rodauth:
  hmac_secret: your-secret-here

# In Rodauth configuration
plugin :rodauth do
  enable :hmac_secret_guard

  hmac_secret Rails.application.credentials.dig(:rodauth, :hmac_secret)
end
```

### With Dotenv

```ruby
# Gemfile
gem 'dotenv'

# config.ru or application.rb
require 'dotenv/load'

# .env
HMAC_SECRET=your-secret-here

# Rodauth configuration
plugin :rodauth do
  enable :hmac_secret_guard
  # Automatically reads from ENV['HMAC_SECRET']
end
```

## Testing

### Disable Validation in Tests

```ruby
# spec/spec_helper.rb or test/test_helper.rb
ENV['RACK_ENV'] = 'test'

# In Rodauth configuration
plugin :rodauth do
  enable :hmac_secret_guard

  if ENV['RACK_ENV'] == 'test'
    validate_secrets_on_configure? false
    hmac_secret 'test-secret-12345'
  end
end
```

### Test Secret Validation

```ruby
RSpec.describe "HMAC Secret Guard" do
  it "raises error in production without secret" do
    expect {
      Class.new(Roda) do
        plugin :rodauth do
          enable :hmac_secret_guard
          production_env_check true
          # No hmac_secret set
        end
      end
    }.to raise_error(Rodauth::ConfigurationError, /HMAC_SECRET/)
  end

  it "uses fallback in development" do
    output = capture_warnings do
      Class.new(Roda) do
        plugin :rodauth do
          enable :hmac_secret_guard
          production_env_check false
          # No hmac_secret set
        end
      end
    end

    expect(output).to include("WARNING")
    expect(output).to include("HMAC secret")
  end
end
```

## Troubleshooting

### Problem: ConfigurationError in production

```text
Rodauth::ConfigurationError: HMAC_SECRET environment variable must be set in production
```

**Solution:** Set HMAC_SECRET environment variable:

```bash
export HMAC_SECRET=$(openssl rand -hex 64)
```

### Problem: Warning in development

```text
[rodauth] WARNING: Using default HMAC secret for development only
```

**Solution:** This is expected behavior. To silence:

1. Set HMAC_SECRET in development:

   ```bash
   echo "HMAC_SECRET=dev-secret" >> .env
   ```

2. Or customize warning message:

   ```ruby
   hmac_secret_dev_warning ''  # Silent
   ```

3. Or disable validation:

   ```ruby
   validate_secrets_on_configure? false
   ```

### Problem: Secret not loading from environment

**Check:**

1. Environment variable is set:

   ```bash
   echo $HMAC_SECRET
   ```

2. Environment variable name matches configuration:

   ```ruby
   hmac_secret_env_key 'HMAC_SECRET'  # Must match env var name
   ```

3. Secret is not already set in configuration:

   ```ruby
   # This prevents auto-loading from ENV
   hmac_secret 'hardcoded-secret'

   # Remove the above line to enable auto-loading
   ```

### Problem: "Insecure development secret" warning in production

**Cause:** Production detection not working correctly.

**Solution:** Verify production check:

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  # Debug production detection
  production_env_check proc {
    puts "RACK_ENV: #{ENV['RACK_ENV']}"
    ENV['RACK_ENV'] == 'production'
  }
end
```

## Implementation Details

### Environment Variable Deletion

The feature reads and **deletes** the environment variable from ENV:

```ruby
env_value = ENV.delete(hmac_secret_env_key)
```

**Rationale:**

- Prevents accidental exposure via environment inspection
- Reduces attack surface
- Secret stored in method, not in ENV hash

### Method Definition

Secret is stored as a method, not instance variable:

```ruby
self.class.send(:define_method, :hmac_secret) { env_value }
```

**Benefits:**

- Consistent with Rodauth's configuration pattern
- Can be overridden in configuration block
- Evaluated lazily when needed

### Validation Timing

Validation runs in `post_configure` hook:

```ruby
def post_configure
  super
  validate_secrets! if validate_secrets_on_configure?
end
```

**Timing guarantees:**

- Runs after all features loaded
- Runs before application starts handling requests
- Fails fast on misconfiguration

## Advanced Usage

### Multiple Secrets

Guard multiple secrets by calling the feature with different configurations:

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  # Validate hmac_secret
  validate_secrets!

  # Also validate jwt_secret if using JWT
  if respond_to?(:jwt_secret)
    unless jwt_secret
      raise Rodauth::ConfigurationError, "JWT_SECRET must be set"
    end
  end
end
```

### Custom Validation Logic

```ruby
plugin :rodauth do
  enable :hmac_secret_guard

  # Override validation method
  validate_secrets! do
    secret = hmac_secret

    # Custom length requirement
    if secret && secret.length < 64
      raise Rodauth::ConfigurationError, "HMAC secret must be at least 64 characters"
    end

    # Custom entropy check
    if secret && secret.chars.uniq.length < 16
      warn "HMAC secret has low entropy"
    end
  end
end
```

### Conditional Enabling

```ruby
plugin :rodauth do
  # Only enable in specific environments
  if ENV['ENABLE_SECRET_GUARD'] == 'true'
    enable :hmac_secret_guard
  end
end
```

## Related Features

- **password_pepper** - Uses `secret` for password peppering (similar security requirements)
- **jwt** - Requires JWT secret (similar validation needs)
- **internal_request** - May bypass HMAC checks (consider interaction)

## References

- [Rodauth HMAC Documentation](http://rodauth.jeremyevans.net/rdoc/files/README_rdoc.html#label-HMAC)
- [OWASP Secrets Management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html)
- [12 Factor App - Config](https://12factor.net/config)
