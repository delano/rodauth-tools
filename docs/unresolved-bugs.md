# Unresolved Bugs: Verified Status and Documented Solutions

**Scope:** Issues [#114](https://github.com/delano/rodauth-tools/issues/114),
[#115](https://github.com/delano/rodauth-tools/issues/115),
[#116](https://github.com/delano/rodauth-tools/issues/116)
**Verified against:** `main` @ `a600397` (2026-07-05). Every line number below was
re-checked against this commit, not copied from the tickets.

The three tickets contain **32 raw line-items**. After removing duplicates
(#116 restates three bugs already tracked in #115) and separating out items that
have since been fixed on `main` (via PR #117 and follow-ups), **23 distinct bugs
remain unresolved**. Each one is documented below with its verified location,
root cause, failure scenario, and a concrete solution.

- [Accounting: 32 raw items → 23 unresolved](#accounting)
- [Verified fixed (for the record)](#verified-fixed)
- [Bug index](#bug-index)
- [Group 1: Secret guards (RT-01 – RT-02)](#group-1-secret-guards)
- [Group 2: table_guard (RT-03 – RT-10)](#group-2-table_guard)
- [Group 3: Table discovery (RT-11 – RT-12)](#group-3-table-discovery)
- [Group 4: Migration codegen (RT-13 – RT-15)](#group-4-migration-codegen)
- [Group 5: external_identity (RT-16 – RT-17)](#group-5-external_identity)
- [Group 6: CI / supply chain (RT-18 – RT-22)](#group-6-ci--supply-chain)
- [Group 7: Console helpers (RT-23)](#group-7-console-helpers)
- [Suggested fix sequencing](#suggested-fix-sequencing)

---

## Accounting

| Ticket | Raw items | Fixed | Duplicates of #115 | Distinct unresolved |
|---|---|---|---|---|
| #114 (issue + audit comment) | 4 | 3 | — | 1 (RT-01) |
| #115 (consolidated audit) | 22 | 3 | — | 19 (RT-02 – RT-07, RT-11 – RT-23) |
| #116 (table_guard hardening) | 6 | 0 | 3 (→ RT-03, RT-04, RT-07) | 3 (RT-08*, RT-09, RT-10) |
| **Total** | **32** | **6** | **3** | **23** |

\* #115's B-item bundling: the ":halt/:exit + unordered drops" bullet in #115
covers two mechanisms that #116 splits into its items 5 and 2. This document
splits them the same way (#116 item 5 → RT-07 exit(1); #116 item 2 → RT-08 drop
ordering), so the arithmetic above assigns RT-08 to #116's distinct column.

The one item this audit had not yet verified against `main` —
`console_helpers.rb` nil-db handling (a listed finding in #115 §F) — **has now
been checked and is unresolved** (RT-23). "Not yet verified" describes this
pass's coverage, not #115, which already reports it.

## Verified fixed

These six raw line-items are confirmed resolved on `main` (no action needed;
listed so nobody re-audits them):

1. **#114 sub-finding A** — hardcoded public fallback secret. Now
   `SecureRandom.hex(32)` per process (`hmac_secret_guard.rb:79`,
   `jwt_secret_guard.rb:79`).
2. **#114 sub-finding B** — whitespace-only/blank secret accepted. Now stripped
   and treated as absent (`secret_guard.rb:41-49`, `blank?` at `:111-113`);
   `minimum_secret_length` available for production.
3. **#114 doc-snippet finding** — the docstring that recommended a fail-open
   `production_env_check` override now recommends the fail-safe form and
   explicitly warns against `ENV['RACK_ENV'] == 'production'`
   (`hmac_secret_guard.rb:28-41`, `jwt_secret_guard.rb:28-41`).
4. **#115 A-🔴** — method-name collision disabling one guard when both enabled.
   Fixed by the kind-parameterized `Rodauth::SecretGuard` module; each guard's
   `post_configure` calls its own `validate_{hmac,jwt}_secret!`. (Residual: the
   legacy `validate_secrets!` alias still collides by design, but boot-time
   validation no longer depends on it and the collision is documented in both
   features' docstrings.)
5. **#115 B — `db.loggers` mutation race** — `table_exists?` now matches against
   a `db.tables`/`db.views` name set (`table_guard.rb:462-471`); no logger
   suppression, no shared-state mutation.
6. **#115 B — rescue calling block mode with 0 args** — fixed via
   `table_guard_mode_symbol` (`table_guard.rb:502-507`, used at `:755`).

---

## Bug index

| ID | Sev | Title | Sources | Location (verified) |
|---|---|---|---|---|
| RT-01 | 🔴* | Production detection is a brittle exact match | #114 | `hmac_secret_guard.rb:74`, `jwt_secret_guard.rb:74` |
| RT-02 | 🟡 | `ENV.delete` makes secrets single-consumer | #115 A | `secret_guard.rb:44` |
| RT-03 | 🟠 | Destructive modes gated by prefix match, no opt-in | #115 B / #116 §3 | `table_guard.rb:679,696,726` |
| RT-04 | 🟠 | `table_exists?` fails open on DB errors | #115 B / #116 §4 | `table_guard.rb:282-285` |
| RT-05 | 🟡 | `enable :table_guard` with no mode is a silent no-op | #115 B | `table_guard.rb:61,104,120-137` |
| RT-06 | 🟡 | Handler-block detection mishandles negative/zero arity | #115 B | `table_guard.rb:127,130,519,590` |
| RT-07 | 🟡 | `:halt`/`:exit` modes call `exit(1)` at boot | #115 B / #116 §5 | `table_guard.rb:573,644` |
| RT-08 | 🟡 | In-feature `drop_tables` unordered and untransacted | #115 B / #116 §2 | `table_guard.rb:708,738,772-785` |
| RT-09 | 🟠 | `:recreate`/`:drop` miss hidden tables (functionally broken) | #116 §1 | `table_guard.rb:704,734` |
| RT-10 | 🟡 | `:drop` blast radius (migration tracking) undocumented/ungated | #116 §6 | `table_guard.rb:740-744` |
| RT-11 | 🟡 | `discover_tables` silently drops raising `*_table` methods | #115 C | `table_inspector.rb:34-40` |
| RT-12 | 🟡 | `table_information` misattributes via value-based `.key()` lookup | #115 C | `table_inspector.rb:52-53` |
| RT-13 | 🟡 | `eval` of ERB migration with unvalidated `table_prefix` | #115 D | `migration.rb:84-90,148-150` |
| RT-14 | 🟡 | Unsanitized identifiers interpolated into generated migrations | #115 D | `sequel_generator.rb:129,149,164,169,194` |
| RT-15 | ⚪ | `format_default_value` executes Proc defaults at codegen | #115 D | `sequel_generator.rb:478` (vs `:248`) |
| RT-16 | 🟡 | Identifier regexes use `^`/`$` line anchors | #115 E | `external_identity.rb:212,220` |
| RT-17 | 🟡 | `find_missing_columns` fails open | #115 E | `external_identity.rb:744-752` |
| RT-18 | 🟠 | Dependabot auto-merge + self-approval, no enforced test gate | #115 F | `dependabot-automerge.yml:22-38` |
| RT-19 | 🟡 | Third-party Actions pinned to mutable tags | #115 F | all four workflows |
| RT-20 | 🟡 | CI gate exists only as out-of-repo branch-protection settings | #115 F | `main.yml` |
| RT-21 | 🟡 | `removeLabel` step lacks `issues: write`; 403 swallowed | #115 F | `claude-code-review.yml:33,79-94` |
| RT-22 | ⚪ | CI matrix tests only Ruby 3.4.7; gemspec floor is 3.2.0 | #115 F | `main.yml:16-17`, gemspec `:34` |
| RT-23 | ⚪ | `create_tables!` forwards a possibly-nil `db` | #115 F (was unchecked) | `console_helpers.rb:45-47,95` |

\* RT-01's original High rating assumed the fallback secret was a public
constant. That half is fixed (ephemeral fallback), so the residual severity is
lower — see the re-assessment inside RT-01 — but the detection bug itself is
unchanged, so the original rating is kept in the index with this caveat.

---

## Group 1: Secret guards

### RT-01 — Production detection is a brittle exact match (fails open for any non-`"production"` value)

- **Sources:** #114 (core finding)
- **Location:** `lib/rodauth/features/hmac_secret_guard.rb:74`,
  `lib/rodauth/features/jwt_secret_guard.rb:74`
- **Severity:** 🔴 High as filed; residual risk reduced (see below) but the bug
  is unchanged.

**Problem.** Both guards default to:

```ruby
auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
```

An *unset* `RACK_ENV` fails safe (substitutes `'production'`). But any
explicitly-set value other than the literal `"production"` — `staging`, `prod`,
`Production`, or a Rails app that sets only `RAILS_ENV` while `RACK_ENV` is set
to something else by the platform — makes `production?` return `false`. The
guard then skips the hard failure entirely: it logs a warning and installs the
development fallback.

**Failure scenario.** A staging or production deployment sets
`RACK_ENV=staging` (or only `RAILS_ENV=production`) and, due to a separate
misconfiguration, `HMAC_SECRET` is unset. Boot succeeds silently. Since the
fallback is now ephemeral-per-process (fixed by #117), the impact today is:
(a) the operator never learns the secret is missing — the exact deployment
error this feature exists to catch; and (b) all HMAC-signed tokens
(verify/reset/remember) or JWTs are signed with a random key that differs per
process and per restart, so tokens break across restarts and across workers in
non-deterministic, hard-to-diagnose ways. Before #117 this was full token
forgery; that part is mitigated, the silent-skip part is not.

**Solution.** Fail closed on *unrecognized* environments instead of failing
open on non-matching ones, and consult the common env-var conventions. Put one
shared detector in `Rodauth::SecretGuard` and use it as the default for both
guards (and `account_id_obfuscation`, which copies the same pattern):

```ruby
# lib/rodauth/secret_guard.rb
DEV_TEST_ENVS = %w[development test].freeze

# Production unless a *recognized* dev/test indicator is present.
# Unset, unrecognized ("staging", "prod"), or differently-cased values
# are all treated as production, so the guard fails closed.
def production_env?
  env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV']
  !DEV_TEST_ENVS.include?(env&.strip&.downcase)
end
```

```ruby
# in both features
auth_value_method :production_env_check, proc { Rodauth::SecretGuard.production_env? }
```

Notes:
- This deliberately treats `staging` as production — for a secrets guard,
  "not verifiably dev/test" must mean "enforce". Operators who want staging
  exempted can override `production_env_check`, which stays configurable.
- `RACK_ENV` keeps precedence over `RAILS_ENV`/`APP_ENV` so existing exact
  configurations keep their meaning; the fallbacks only engage when `RACK_ENV`
  is unset.
- The same detector should replace the prefix-match gate in `table_guard`
  (RT-03), fulfilling #115's structural opportunity (c): one consistent,
  exact-match, multi-var production detector shared across features.

**Regression tests.** Assert `production?` is true for: unset env;
`RACK_ENV=staging`; `RACK_ENV=prod`; `RACK_ENV=Production`; unset `RACK_ENV`
with `RAILS_ENV=production`. Assert false for `RACK_ENV=development`/`test`
(any case, surrounding whitespace). Assert a missing secret raises
`ConfigurationError` in each true case.

### RT-02 — `ENV.delete` makes each secret single-consumer

- **Sources:** #115 §A (🟡)
- **Location:** `lib/rodauth/secret_guard.rb:44` (`load_from_env!`)

**Problem.** `load_from_env!` reads the secret with `ENV.delete`. The first
Rodauth Auth class to configure consumes the variable; a second configuration
in the same process (the classic user-auth + admin-auth split, or any
`internal_request`-style secondary class) sees `nil`. Order-dependent, and
invisible to every single-config test.

**Failure scenario.** App defines `RodauthMain` and `RodauthAdmin`, both with
`enable :hmac_secret_guard`, sharing one `HMAC_SECRET`. In production the
second class boots with no secret and raises `ConfigurationError` (startup
crash); in development it silently gets a *different* random fallback than the
first class, so tokens minted by one class fail verification in the other.

**Solution.** Keep the scrub-from-ENV property but cache the value process-wide
on first read so later consumers get the same secret:

```ruby
# lib/rodauth/secret_guard.rb
ENV_SECRET_CACHE = {}
ENV_SECRET_CACHE_MUTEX = Mutex.new

def read_env_secret(env_key)
  ENV_SECRET_CACHE_MUTEX.synchronize do
    unless ENV_SECRET_CACHE.key?(env_key)
      raw = ENV.delete(env_key)
      value = raw&.strip
      ENV_SECRET_CACHE[env_key] = (value.nil? || value.empty?) ? nil : value
    end
    ENV_SECRET_CACHE[env_key]
  end
end

def load_from_env!(rodauth, kind)
  return unless blank?(rodauth.send(:"#{kind}_secret"))

  value = read_env_secret(rodauth.send(:"#{kind}_secret_env_key"))
  return if value.nil?

  define_secret(rodauth, kind, value)
end
```

Cache the resolved (stripped) value keyed by env-var name, not by kind, so two
kinds pointing at one variable also work. If holding the secret in a module
constant is deemed no better than leaving it in `ENV`, the alternative is a
`scrub_secret_env?` auth_value_method defaulting to `false` (plain `ENV[]`
read); either resolves the bug — the cache preserves current scrubbing
behavior, the config flag is simpler. Document whichever is chosen.

**Regression tests.** Configure two Auth classes sequentially against one env
var: both must end up with the same, correct secret; the var must be gone from
`ENV` afterwards (cache variant). **Test-isolation caveat for the cache
variant:** `ENV_SECRET_CACHE` is process-lifetime state, so a spec that
exercises `load_from_env!` will poison later specs unless it is reset. Add
`after { Rodauth::SecretGuard::ENV_SECRET_CACHE.clear }` (or a small
`SecretGuard.reset_env_cache!` test helper) to any spec that touches it;
otherwise this suite passes in isolation but fails under a different run order.

---

## Group 2: table_guard

### RT-03 — Destructive modes (`:sync`/`:recreate`/`:drop`) gated by a prefix match with no explicit opt-in

- **Sources:** #115 §B (🟠) / #116 item 3 (needs maintainer ruling; reverses #24)
- **Location:** `lib/rodauth/features/table_guard.rb:679` (`:sync`), `:696`
  (`:recreate`), `:726` (`:drop`)

**Problem.** The only gate before dropping tables is:

```ruby
unless %w[dev development test].any? { |env| ENV['RACK_ENV']&.start_with?(env) }
```

- **Prefix** match: `RACK_ENV=test-staging`, `devops-prod`,
  `development-mirror` all pass and will drop tables.
- Only `RACK_ENV` is consulted; `RAILS_ENV`/`APP_ENV` conventions are ignored.
- Unset `RACK_ENV` makes the gate refuse with only an error log — the
  destructive mode silently no-ops rather than failing loudly (confusing in the
  benign direction too).
- `:recreate`/`:drop` are deliberately excluded from the "everything exists →
  return early" short-circuit (`table_guard.rb:171`), so when the gate passes
  they drop **all** auth tables on **every boot**, with no confirmation.

**Failure scenario.** A staging box is provisioned with `RACK_ENV=test-staging`
and a config copied from development that still has
`table_guard_sequel_mode :recreate`. Every process boot drops and recreates all
auth tables: total loss of accounts, password hashes, and 2FA/lockout state on
a data-bearing database.

**Solution.** (Option (a) from #116 — strongest; requires the maintainer ruling
because #24 documents the prefix gate as intended.) Two independent conditions,
both required, checked in one place:

```ruby
DESTRUCTIVE_ENV_ALLOWLIST = %w[development test].freeze

auth_value_method :table_guard_allow_destructive, false

def destructive_mode_permitted?(mode)
  env = ENV['RACK_ENV'] || ENV['RAILS_ENV'] || ENV['APP_ENV']
  unless DESTRUCTIVE_ENV_ALLOWLIST.include?(env&.strip&.downcase)
    rodauth_error("[table_guard] #{mode} refused: environment #{env.inspect} is not " \
                  "in the exact-match allowlist #{DESTRUCTIVE_ENV_ALLOWLIST}")
    return false
  end
  unless table_guard_allow_destructive
    rodauth_error("[table_guard] #{mode} refused: set `table_guard_allow_destructive true` " \
                  'to permit dropping tables in this environment')
    return false
  end
  rodauth_warn("[table_guard] #{mode}: destructive operation permitted against " \
               "#{db.opts.values_at(:host, :database).compact.join('/')}")
  true
end
```

Use `return unless destructive_mode_permitted?(:sync)` (etc.) in all three
branches. Additional hardening worth bundling: refuse `:recreate`/`:drop` when
the target tables are non-empty unless a separate force flag is set, and always
log the DB host/database being targeted (done above). If the maintainer picks
option (b) instead (no new opt-in), keep everything except the
`table_guard_allow_destructive` check — the exact-match allowlist alone already
closes the `test-staging` hole. Update the docs that #24 added so documented
behavior matches whichever option lands.

**Regression tests.** For each of the three modes: passes with
`RACK_ENV=development` + opt-in; refuses (and drops nothing) for
`RACK_ENV=test-staging`, `production`, unset, and for missing opt-in; the
refusal message names the env value and the missing condition.

### RT-04 — `table_exists?` fails open: DB errors report tables as present

- **Sources:** #115 §B (🟠) / #116 item 4 (explicitly deferred from PR #117)
- **Location:** `lib/rodauth/features/table_guard.rb:282-285`

**Problem.**

```ruby
rescue StandardError => e
  rodauth_warn("[table_guard] Unable to check table existence for #{table_name}: #{e.message}")
  true # Assume exists to avoid false positives (see hardening follow-up #116)
```

A connection failure, permission error, bad `search_path`, or nil `db` makes a
genuinely missing table report as present. `missing_tables` then returns `[]`,
the "✅ All required tables exist" banner prints, `:raise`/`:error` never fire,
and `:create`/`:sync` never create anything. The guard no-ops precisely on the
class of faults it exists to catch. (The rescue also swallows errors from
`existing_table_names` — one failed catalog query silently passes *every*
table, N times.)

**Failure scenario.** The app boots pointed at a database whose user lacks
catalog privileges (or the DB is briefly unreachable). `db.tables` raises,
every `table_exists?` returns `true`, boot prints the all-clear, and the first
real query 500s in production with no prior warning — while the operator
believes the guard validated the schema.

**Solution.** Fail closed and make "could not check" a distinct state rather
than mapping it to either boolean:

1. In `missing_tables`/`table_status`, fetch `existing_table_names` **outside**
   the per-table loop without a blanket rescue: if the catalog query itself
   fails, raise a `Rodauth::ConfigurationError` wrapping the cause ("table_guard
   could not enumerate tables: <error>"). A guard that cannot see the database
   should stop the boot conversation loudly, not certify it.
2. In `table_exists?`, narrow the rescue to the qualified-name probe path (the
   only remaining per-table query) and return `false` there, recording the
   error:

```ruby
rescue StandardError => e
  table_check_errors << { table: table_name, error: e }
  rodauth_error("[table_guard] Could not verify #{table_name}: #{e.class}: #{e.message}")
  false # fail closed: unverifiable counts as missing
```

3. In `check_required_tables!`, never print the success banner when
   `table_check_errors` is non-empty, and skip `handle_sequel_generation` for
   error-derived "missing" entries so `:create`/`:sync`/`:recreate` don't run
   DDL against a database that just demonstrated it can't answer catalog
   queries.

Semantics change (currently a broken DB passes silently), so note it in the
changelog; #116 already endorses failing closed.

**Regression tests.** Stub `db.tables` to raise → `check_required_tables!`
raises with a clear message and prints no all-clear. Stub the qualified probe
to raise → table counted missing, `:raise` mode raises, no DDL executed.

### RT-05 — `enable :table_guard` with no mode is a complete silent no-op

- **Sources:** #115 §B (🟡)
- **Location:** `lib/rodauth/features/table_guard.rb:61` (default `nil`),
  `:104` (`post_configure`), `:120-137` (`should_check_tables?`)

**Problem.** `table_guard_mode` defaults to `nil`; `should_check_tables?`
returns `false` for `nil`; `post_configure` then does nothing (unless a
`sequel_mode` is set). An operator who writes `enable :table_guard` expecting
protection gets silence — indistinguishable from "everything validated".

**Failure scenario.** Developer enables the feature, sees no output, assumes
tables are fine; the missing `account_lockouts` table surfaces as a runtime
500 during a lockout flow instead of a boot-time report.

**Solution.** Make the default useful: `auth_value_method :table_guard_mode,
:warn`. `:silent`/`:skip` remain as the explicit opt-outs, so nobody loses the
ability to disable it — they just have to say so. Update the feature docstring
and README accordingly. If changing the default is judged too breaking for
existing users who rely on nil-means-off, the fallback is a one-time boot
notice ("table_guard enabled but no table_guard_mode configured; not checking
anything — set :warn/:error/:raise or :silent to silence this message"), but
the default-to-`:warn` variant is strictly better aligned with the feature's
stated purpose and is the recommended fix.

**Regression tests.** `enable :table_guard` with no further config against a
DB missing a table → warning emitted. With `table_guard_mode :silent` → no
output.

### RT-06 — Custom-handler detection mishandles negative arity and executes 0-arity blocks to inspect them

- **Sources:** #115 §B (🟡)
- **Location:** `lib/rodauth/features/table_guard.rb:127,130` (`should_check_tables?`),
  `:519-524` (`handle_column_guard_mode`), `:590-595` (`handle_table_guard_mode`)

**Problem.** Handler blocks are detected with `method(:table_guard_mode).arity > 0`.

- A handler with optional or splat params — `|missing, config = nil|` (arity
  −2) or `|*args|` (arity −1) — fails the `> 0` test, so the code falls through
  to `mode_value = table_guard_mode` (a zero-arg call). For a required-param
  block that raises `ArgumentError` at boot; for `|*args|` it runs with `[]`
  instead of the missing-tables list. Documented handler shapes crash or
  mis-run.
- A 0-arity handler block is *executed* merely to read the mode
  (`should_check_tables?` line 130), and executed again during handling
  (`:541`/`:612`) — side effects fire at least twice per check.

**Solution.** Detect "expects arguments" with the method's parameter list, and
dispatch with an arity-clamped argument array; resolve the mode value once per
check pass instead of re-invoking:

```ruby
def table_guard_mode_expects_args?
  method(:table_guard_mode).parameters.any?
end

def call_table_guard_handler(missing, context)
  m = method(:table_guard_mode)
  args = [missing, context]
  m.arity.negative? ? m.call(*args) : m.call(*args.take(m.arity))
end
```

- `parameters.any?` is true for `|a|`, `|a, b|`, `|a, b = nil|`, and `|*a|`
  alike, and false for plain value methods — replacing all three `arity > 0`
  sites (`:127`, `:519`, `:590`).
- Negative arity (optional/splat) receives the full `[missing, context]`;
  non-negative arity receives exactly what it declares. This replaces the
  `case mode_method.arity / when 1` dispatch at `:521-524` and `:592-595`.
- In `check_required_tables!`, evaluate `table_guard_mode` at most once for
  0-parameter configurations and pass the resolved value into both
  `handle_table_guard_mode` and `handle_column_guard_mode`, so a 0-arity Proc
  handler runs exactly once per check, and never runs at all from
  `should_check_tables?` (which only needs `parameters.any? || <resolved value
  test>`).

**Regression tests.** Handlers of shape `|m|`, `|m, c|`, `|m, c = nil|`,
`|*a|`: all must receive the real missing-tables list and not raise. A 0-arity
block with a side-effect counter: runs exactly once per `check_required_tables!`.

### RT-07 — `:halt`/`:exit` modes call `exit(1)` from `post_configure`

- **Sources:** #115 §B (🟡) / #116 item 5
- **Location:** `lib/rodauth/features/table_guard.rb:573` (columns), `:644` (tables)

**Problem.** Both mode handlers terminate the whole process with `exit(1)`.
In a multi-tenant or embedded host (Rodauth configured inside a larger Rack
process, background-job process, or test harness), one tenant's missing table
kills every co-hosted app. The feature's own docstring concedes "not
recommended for multi-tenant" — the mechanism, not the advice, is the problem.
`exit` raises `SystemExit`, which also slips past `rescue StandardError`
cleanup handlers the host may rely on.

**Solution.** Raise a dedicated, rescuable exception and let the process owner
decide to exit:

```ruby
module Rodauth
  # Raised by table_guard's :halt/:exit modes instead of terminating the process.
  class TableGuardHaltError < ConfigurationError; end
end

when :halt, :exit
  rodauth_error(build_missing_tables_error(missing))
  raise Rodauth::TableGuardHaltError, build_missing_tables_message(missing)
```

Subclassing `ConfigurationError` keeps `rescue Rodauth::ConfigurationError`
call sites working. A standalone launcher that truly wants exit-code-1 gets it
for free — an unrescued exception terminates non-zero — and hosts that must
not die can rescue. Document the behavior change under `:halt`/`:exit` in the
docstring at the top of the file (which currently advertises "Halt/exit
startup").

**Regression tests.** `:halt` mode with a missing table raises
`TableGuardHaltError` (and is caught by `rescue Rodauth::ConfigurationError`);
process-level `exit` is never invoked (stub `Kernel#exit` to fail the test if
called).

### RT-08 — In-feature `drop_tables` drops in hash order with no transaction

- **Sources:** #115 §B (🟡, bundled) / #116 item 2
- **Location:** `lib/rodauth/features/table_guard.rb:708,738`
  (`drop_tables(all_tables.reverse)`), `:772-785` (`drop_tables`)

**Problem.** `:recreate` and `:drop` compute `all_tables` from
`table_configuration` (a Hash) and "order" the drop with `.reverse` — i.e.
reversed hash-insertion order, which has no relationship to FK dependency
order. Each `db.drop_table` runs independently with no wrapping transaction.
CASCADE masks the mis-ordering on PostgreSQL/MySQL, but on SQLite (no CASCADE
support; `cascade_supported?` correctly returns false) a parent-before-child
drop raises mid-loop and leaves a **partially dropped schema** — the worst of
both worlds: data destroyed *and* the recreate step then fails.

**Solution.** This is the same change as RT-09 — route the drop through
`SequelGenerator`, which already has correct ordering
(`order_tables_for_drop`, `sequel_generator.rb:386-409`) and full-table-set
enumeration; and wrap the drop+create cycle in a transaction:

```ruby
when :recreate
  return unless destructive_mode_permitted?(:recreate)   # RT-03

  generator = Rodauth::SequelGenerator.new(missing, self, missing_cols)
  db.transaction do
    generator.execute_drops(db)      # template-enumerated, FK-ordered (RT-09)
    # ... recreate via execute_creates as today ...
  end
```

Keep the private `drop_tables` helper only if something else needs it, and if
kept, make it delegate ordering to `SequelGenerator#order_tables_for_drop` and
accept a transaction from the caller. (Transactional DDL is a no-op guarantee
on MySQL, which auto-commits DDL — note that in the docstring — but it makes
SQLite and PostgreSQL atomic, which is where the bug bites.)

**Regression tests.** On SQLite with `foreign_keys` enforced and the standard
base schema: `:recreate` completes; killing it mid-drop (stub a failure on the
Nth drop) leaves the schema untouched (PostgreSQL/SQLite).

### RT-09 — `:recreate`/`:drop` build their table list from `*_table` methods, missing hidden tables

- **Sources:** #116 item 1 (flagged "likely broken, not just a hardening gap")
- **Location:** `lib/rodauth/features/table_guard.rb:704,734`

**Problem.** Both modes enumerate
`table_configuration.map { |_, info| info[:name] }` — the discovered `*_table`
methods. By the project's own "Hidden Tables" design (see `CLAUDE.md`),
`account_statuses` and `account_password_hashes` have **no** `*_table` method,
so they are absent from that list. `:recreate` therefore drops `accounts` but
leaves the two hidden tables in place, then `execute_creates` re-runs
`base.erb`, whose `create_table(:account_statuses)` fails because the table
still exists. The `:sync` branch does not have this bug — it already calls
`generator.execute_drops(db)` (`:688`), which enumerates via
`TemplateInspector`.

**Failure scenario.** Standard schema (base feature), SQLite or PostgreSQL,
`table_guard_sequel_mode :recreate` in development: first boot after tables
exist crashes in `handle_sequel_generation` with a "table account_statuses
already exists" error (then swallowed or re-raised per mode — see RT-04/RT-06
interactions). The mode is effectively unusable with the default schema.

**Solution.** Use the template-based path for all three destructive modes, as
`:sync` already does:

```ruby
when :recreate
  return unless destructive_mode_permitted?(:recreate)

  generator = Rodauth::SequelGenerator.new(missing_tables_snapshot_or_all, self, missing_cols)
  generator.execute_drops(db)   # TemplateInspector.all_tables_for_features → hidden tables included
  ...
when :drop
  return unless destructive_mode_permitted?(:drop)

  generator.execute_drops(db)
  drop_tables(%i[schema_info schema_migrations])   # see RT-10
```

One wrinkle: `SequelGenerator#execute_drops` derives its feature set from
`missing_tables` (`extract_features_from_missing_tables`), and in the
`:recreate`/`:drop` case nothing may be "missing". Give `SequelGenerator` an
explicit way to enumerate for *enabled features* rather than missing ones,
e.g. `execute_drops(db, features: enabled_template_features)` where the
default keeps today's behavior. That keeps `:sync` untouched and lets
`:recreate`/`:drop` pass the full feature list. Combined with RT-08's
transaction, this makes both modes correct for the standard schema for the
first time.

**Regression tests.** With base feature tables (including both hidden ones)
present: `:recreate` boots cleanly and ends with all tables present;
`:drop` leaves zero rodauth tables (hidden ones included) — assert
via `db.tables` directly, not via `table_configuration`.

### RT-10 — `:drop` also destroys migration tracking, undocumented and behind the same weak gate

- **Sources:** #116 item 6
- **Location:** `lib/rodauth/features/table_guard.rb:740-744`

**Problem.** `:drop` additionally executes
`drop_tables(%i[schema_info schema_migrations])`, wiping Sequel's migration
history so all migrations re-run from scratch. #116 confirms the behavior is
intended for the "auto-migrations at boot" workflow, but (a) it is documented
only in a code comment (`:723-724`), not in the feature docstring, README, or
the `:drop` log output; and (b) it rides on the same prefix gate as RT-03 —
so `schema_info`/`schema_migrations` for the **entire application** (not just
rodauth tables) are dropped under conditions as weak as `RACK_ENV=test-staging`.

**Solution.** Three small pieces, on top of RT-03's gate:

1. **Document the blast radius** where users configure it — the mode list in
   the file-top docstring and README: ":drop removes all rodauth tables AND
   Sequel's `schema_info`/`schema_migrations`, so *all* application migrations
   re-run on next boot."
2. **Say it at runtime** — the existing log lines (`:743-744`) should name the
   two tracking tables explicitly.
3. **Gate it separately** — the tracking tables belong to the whole app, not to
   rodauth, so their removal deserves its own switch:

```ruby
auth_value_method :table_guard_drop_migration_tracking, true  # current behavior
# in :drop, after RT-03's destructive_mode_permitted? check:
drop_tables(%i[schema_info schema_migrations]) if table_guard_drop_migration_tracking
```

Default `true` preserves documented behavior (the mode exists *for* the
re-migrate workflow); teams that want `:drop` limited to rodauth tables can
turn it off. If the maintainer prefers fail-closed here too, flip the default
to `false` in the same release that lands RT-03's opt-in, since users must
touch their config for destructive modes anyway.

**Regression tests.** `:drop` with tracking enabled removes both tracking
tables; with it disabled leaves them; log output names them.

---

## Group 3: Table discovery

### RT-11 — `discover_tables` silently drops `*_table` methods that raise

- **Sources:** #115 §C (🟡)
- **Location:** `lib/rodauth/table_inspector.rb:34-40`

**Problem.**

```ruby
rescue StandardError => e
  warn "TableInspector: Unable to call #{method}: #{e.message}" if ENV['RODAUTH_DEBUG']
```

A `*_table` method that raises at boot — typical for a multi-tenant override
that consults request context which doesn't exist during `post_configure` —
is removed from the required-table set with **zero output** unless
`RODAUTH_DEBUG` happens to be set. That table is then never validated, never
generated, never dropped/recreated: the guard's coverage silently shrinks and
nothing downstream can tell.

**Solution.** Surface failures unconditionally while **keeping the `Hash`
return type** — RT-12's fix calls `discover_tables` and iterates it as
`{method => table_name}`, so the return shape must not change:

```ruby
def self.discover_tables(rodauth_instance)
  table_methods = rodauth_instance.methods.select { |m| m.to_s.end_with?('_table') }

  tables = {}
  table_methods.each do |method|
    table_name = rodauth_instance.send(method)
    tables[method] = table_name if table_name.is_a?(String) || table_name.is_a?(Symbol)
  rescue StandardError => e
    (@discovery_errors ||= {})[method] = e
    Kernel.warn "[table_guard] TableInspector: #{method} raised #{e.class}: #{e.message} — " \
                'this table will NOT be validated or generated'
  end

  tables  # unchanged shape; RT-12 iterates this hash directly
end

# Companion accessor for callers that want the structured errors, so nothing
# depends on a changed return type:
def self.discovery_errors
  @discovery_errors || {}
end
```

`table_guard` should then include "N table methods could not be evaluated" in
`check_required_tables!` output and withhold the ✅ banner when
`discovery_errors` is non-empty (same principle as RT-04: never print an
all-clear over an unverified set). *If* you would rather return `[tables,
errors]` as a tuple, that is fine too — but then RT-12's
`discovered = discover_tables(...)` call must destructure it
(`tables, = discover_tables(...)`) or the `.to_h` there iterates the array and
breaks. The Hash-preserving form above avoids that coupling.

**Regression tests.** An Auth class with a raising `*_table` method: warning is
emitted without `RODAUTH_DEBUG`; `check_required_tables!` output mentions the
skipped method; no ✅ banner.

### RT-12 — `table_information` recovers the method name via value-based `.key()` lookup

- **Sources:** #115 §C (🟡)
- **Location:** `lib/rodauth/table_inspector.rb:52-53`

**Problem.**

```ruby
discovered.transform_values do |table_name|
  method_name = discovered.key(table_name)
```

`Hash#key` returns the *first* key whose value matches. When two `*_table`
methods resolve to the same table name (legitimate: shared tables between
features, or a user pointing two features at one table), every occurrence is
attributed to the first method — wrong `feature:`/`template:` metadata, which
`SequelGenerator.extract_features_from_missing_tables` then uses to pick ERB
templates: the second feature's template can be omitted from generation
entirely.

**Solution.** The key is already available during iteration — iterate pairs
instead of reverse-engineering:

```ruby
def self.table_information(rodauth_instance)
  discovered = discover_tables(rodauth_instance)

  discovered.to_h do |method_name, table_name|
    feature = infer_feature_from_method(method_name, rodauth_instance)
    template_name = "#{feature}.erb"
    template_exists = Rodauth::Tools::Migration.template_exists?(feature)

    info = {
      name: table_name,
      feature: feature,
      template: template_name,
      structure: infer_table_structure(method_name, table_name)
    }
    unless template_exists
      info[:template_missing] = true
      info[:warning] = "No ERB template found for feature: #{feature} (#{template_name})"
    end

    [method_name, info]
  end
end
```

Pure refactor of the same output shape; removes the `.key()` call entirely.

**Regression tests.** Two features whose table methods both return
`:shared_things`: each entry in `table_information` carries its own method's
feature attribution.

---

## Group 4: Migration codegen

*(Trust boundary, per #115: inputs are developer-set configuration and output
is a migration that same developer runs — hardening, not end-user RCE.)*

### RT-13 — `eval` of ERB-rendered migration with unvalidated `table_prefix`

- **Sources:** #115 §D (🟡)
- **Location:** `lib/rodauth/tools/migration.rb:84-90` (`eval`), `:148-150`
  (`table_prefix`); fed from `sequel_generator.rb:304-311` /
  `:356-363` (prefix singularized from `accounts_table`)

**Problem.** `execute_create_tables` splices ERB output into a Ruby string and
`eval`s it. The templates interpolate `table_prefix`, which is derived — with
no validation — from `@prefix` or from singularizing `accounts_table`. Any
non-identifier content in the prefix (`"account; Kernel.system('...')"`,
or simply a typo with a space) becomes live Ruby inside the eval. Same class
of issue as RT-14 but with an immediate execution path.

**Solution.** Two layers; the first is a one-line guard, the second is the
structural fix #115 recommends:

1. **Validate at the boundary.** In `Migration#initialize` (and in
   `SequelGenerator#extract_table_prefix` before returning):

```ruby
# Same rule as RT-14 (see note there): a valid, unquoted SQL identifier.
IDENTIFIER_RE = /\A[a-z_][a-z0-9_]*\z/i

def validate_prefix!(prefix)
  return if prefix.to_s.match?(IDENTIFIER_RE)

  raise ArgumentError, "table prefix must be a valid identifier (got #{prefix.inspect})"
end
```

2. **Shrink the eval surface.** The `eval` wraps the rendered code in
   `Sequel.migration { up { ... } }`. Rather than string-splicing, evaluate the
   rendered template body with `instance_eval` against the migration DSL
   object, or (better, larger refactor) have templates emit data that is
   replayed through Sequel's DSL with symbol arguments. Given the class is
   deprecated in favor of table_guard's sequel modes, layer 1 plus a comment is
   the proportionate fix; layer 2 belongs to the "replace string-built
   migrations with Sequel DSL calls" structural item in #115 if the generator
   is ever un-deprecated.

**Regression tests.** `Migration.new(features: [:base], prefix: 'acc ount')`
raises `ArgumentError`; valid prefixes still generate; a
`accounts_table :"weird name"` config makes `SequelGenerator` raise rather
than emit.

### RT-14 — Unsanitized table/column identifiers interpolated into generated migration code

- **Sources:** #115 §D (🟡)
- **Location:** `lib/rodauth/sequel_generator.rb:129` (`drop_table?(:#{...})`),
  `:149` (`alter_table(:#{...})`), `:164` (`add_column :#{...}`),
  `:169` (`add_index :#{...}`), `:194` (`drop_column :#{...}`); input
  normalization only `.to_sym`s (`table_guard.rb:338-339`)

**Problem.** Identifiers flow into generated Ruby via bare `:#{name}`
interpolation. A symbol like `:"accounts\n; payload"` (which RT-16's broken
regex will happily pass upstream) renders as two lines of live code in the
migration; even without malice, a merely-unusual identifier (`:"my-table"`)
produces a syntax error in the generated file.

**Solution.** Emit identifiers with `.inspect` (which quotes non-simple
symbols correctly) and validate at registration:

```ruby
# generation sites
"drop_table?(#{table_name.to_sym.inspect})"
"alter_table(#{table_name.to_sym.inspect}) do"
"  add_column #{col[:column].to_sym.inspect}, #{column_type}#{options_str}"

# registration (table_guard.rb#register_required_column)
IDENTIFIER_RE = /\A[a-z_][a-z0-9_]*\z/i
[table_name, column_def[:name]].each do |ident|
  unless ident.to_s.match?(IDENTIFIER_RE)
    raise ArgumentError, "invalid SQL identifier: #{ident.inspect}"
  end
end
```

**Note — one rule, not two.** This is the *same* `IDENTIFIER_RE` used by RT-13's
prefix validation (case-insensitive: an unquoted SQL identifier, mixed case
allowed since case is a style choice, not an injection vector). If both fixes
land, define it once in a shared location (e.g. a `Rodauth::Tools` constant)
rather than copying the literal into `migration.rb`/`SequelGenerator` and
`table_guard.rb`, so the two can't silently drift on case semantics later.

`.inspect` guarantees the emitted literal round-trips as a Symbol no matter
the content (defense in depth); the registration validation keeps garbage out
of the pipeline early with a good error message. The execute path
(`execute_alter_tables`) already passes symbols to Sequel's DSL and is fine.

**Regression tests.** Registering `:"bad name"` raises; a crafted
`:"x\n); end"` never appears unquoted in `generate_migration` output (assert
the rendered string parses: `RubyVM::AbstractSyntaxTree.parse(output)`).

### RT-15 — `format_default_value` executes Proc defaults during code generation

- **Sources:** #115 §D (⚪)
- **Location:** `lib/rodauth/sequel_generator.rb:478`
  (`when Proc then "-> { #{value.call} }"`), inconsistent with the execute
  path at `:248` (`column_opts[:default] = col[:default]` — Proc passed
  through untouched)

**Problem.** Generating a migration should be a pure operation, but a Proc
default is `.call`ed during `:log` and `:migration` modes — side effects fire
just from *printing* a migration. The result is also wrong in kind: the
Proc's return value is interpolated into a *new* lambda literal (`-> { 42 }`),
freezing generation-time state into what looks like a dynamic default. The
execute path meanwhile hands the raw Proc to Sequel's `add_column`, which is
not a supported default type — so the two paths disagree about what a Proc
default even means.

**Solution.** Define one meaning and enforce it at registration. Sequel
migration defaults are values or SQL expressions (`Sequel.lit`, functions),
not Ruby Procs — so reject Procs early with guidance:

```ruby
# table_guard.rb#register_required_column
if column_def[:default].is_a?(Proc)
  raise ArgumentError,
        "column default for #{table_name}.#{column_def[:name]} must be a literal value or " \
        'Sequel expression (e.g. Sequel.lit("now()")), not a Proc — Procs cannot be ' \
        'represented in a migration nor executed by the database'
end
```

Then delete the `when Proc` branch in `format_default_value` (unreachable) and
extend the formatter to render `Sequel::LiteralString`/`Sequel::SQL::Expression`
correctly (`"Sequel.lit(#{value.to_s.inspect})"`). This makes generate and
execute agree by construction and removes the codegen-time side effect.

**Regression tests.** Registering a Proc default raises with the guidance
message; a `Sequel.lit('now()')` default renders as `Sequel.lit("now()")` in
generated output and executes successfully.

---

## Group 5: external_identity

### RT-16 — Identifier validation uses `^`/`$` line anchors

- **Sources:** #115 §E (🟡)
- **Location:** `lib/rodauth/features/external_identity.rb:212`
  (`/^[a-z_][a-z0-9_]*$/i`), `:220` (`/^[a-z_][a-z0-9_]*[?!=]?$/i`)

**Problem.** In Ruby, `^`/`$` anchor *lines*, not the whole string. The symbol
`:"accounts\n; payload"` contains a line (`accounts`) that satisfies
`/^[a-z_][a-z0-9_]*$/i`, so it passes "must be a valid Ruby identifier"
validation and flows into `define_method` names, `account_select` column
lists, and — via table_guard registration — the generated-migration pipeline
that RT-14 hardens. The check exists precisely to stop such values and is
defeated by its own anchors.

**Solution.** Whole-string anchors:

```ruby
unless column.to_s =~ /\A[a-z_][a-z0-9_]*\z/i
  raise ArgumentError, "external_identity_column must be a valid Ruby identifier: #{column}"
end
...
unless method_name.to_s =~ /\A[a-z_][a-z0-9_]*[?!=]?\z/i
  raise ArgumentError, "Method name must be a valid Ruby identifier: #{method_name}"
end
```

Grep the repo for other `^...$` *validation* regexes while here — the audit
found only these two, but the pattern is easy to reintroduce, so the
regression spec below is the durable guard.

**Regression tests.** `external_identity_column :"evil\nname"` and
`method_name: :"a\nb"` both raise `ArgumentError`; plain identifiers still
pass.

### RT-17 — `find_missing_columns` fails open: "couldn't verify" reported as "nothing missing"

- **Sources:** #115 §E (🟡)
- **Location:** `lib/rodauth/features/external_identity.rb:744-752`

**Problem.**

```ruby
def find_missing_columns
  return [] unless db # Skip if no database available

  schema = begin
    db.schema(accounts_table)
  rescue StandardError
    return []
  end
```

`check_columns_exist!` (the default boot check) treats `[]` as "all columns
present". A nil `db`, a dropped connection, or a permissions error therefore
silently disables the column check — same fail-open pattern as RT-04, in the
feature whose entire job is to guarantee those columns exist before the app
serves traffic.

**Solution.** Distinguish "verified clean" from "could not verify". Smallest
honest version — let verification failures speak:

```ruby
def find_missing_columns
  if db.nil?
    warn_external_identity('external_identity: no database configured; column check skipped')
    return []
  end

  schema = begin
    db.schema(accounts_table)
  rescue StandardError => e
    raise ArgumentError,
          "external_identity could not verify columns on #{accounts_table} " \
          "(#{e.class}: #{e.message}). Fix the database connection, or set " \
          'external_identity_check_columns to false to skip the check.'
  end
  ...
end
```

Raising on a schema error is correct for `check_columns_exist!` (the operator
asked for a hard check). For the `:autocreate` path, `check_and_autocreate_columns!`
should likewise not register anything when verification failed — the raise
achieves that. The nil-`db` warning (rather than raise) covers legitimate
DB-less template-generation usage; if that usage doesn't exist in practice,
raise there too. Keep the return type `Array` so callers don't change.

**Regression tests.** Stub `db.schema` to raise → `check_columns_exist!`
raises with the could-not-verify message (not "columns not found"); nil db →
warning emitted, check skipped explicitly in the log; healthy db unchanged.

---

## Group 6: CI / supply chain

### RT-18 — Dependabot auto-merge + self-approval of minor AND patch updates with no enforced test gate

- **Sources:** #115 §F (🟠)
- **Location:** `.github/workflows/dependabot-automerge.yml:7-9`
  (`pull-requests: write`, `contents: write`), `:22-29` (auto-merge for patch
  *and* minor), `:31-38` (workflow approves the PR itself)

**Problem.** For every patch/minor Dependabot PR across the bundler,
npm_and_yarn, and github-actions ecosystems, the workflow (a) enables
auto-merge and (b) approves the PR with the bot token. Nothing in the repo
makes the Ruby build a required check (`main.yml` has no connection to this
workflow; branch protection exists only as an out-of-repo assumption — RT-20),
and the self-issued approval satisfies a "require 1 review" rule if one
exists. Net: a compromised minor/patch release of any dependency can squash
itself into `main` with zero human eyes.

**Solution.**
1. **Delete the "Approve" step** (`:31-38`). Auto-*merge* waits for required
   checks; auto-*approve* exists only to defeat the review requirement. If the
   repo requires a review, that review should be human.
2. **Narrow auto-merge to patch only** (drop the
   `semver-minor` condition at `:25`), or drop auto-merge entirely for the
   github-actions ecosystem, where a "minor" tag move is exactly how action
   compromises ship (see RT-19).
3. **Make CI required** so `gh pr merge --auto` actually waits on it: land
   RT-20's branch-protection-as-code naming the `Ruby 3.4.7` (matrix) job as a
   required status check.
4. Reduce `permissions:` to what remains (auto-merge needs
   `contents: write` + `pull-requests: write`; approval permission disappears
   with step 1).

**Regression check.** After the change, open a test Dependabot-authored PR
(or dry-run with `act`): merge must block until the Ruby workflow passes, and
the PR must show no bot approval.

### RT-19 — Third-party Actions pinned to mutable tags

- **Sources:** #115 §F (🟡)
- **Location:** `dependabot-automerge.yml:18` (`dependabot/fetch-metadata@v3`),
  `claude-code-review.yml:44` + `claude.yml:48`
  (`anthropics/claude-code-action@beta`), `claude-code-review.yml:82`
  (`actions/github-script@v9`), `main.yml:20` (`actions/checkout@v7`),
  `main.yml:24` (`ruby/setup-ruby@v1`)

**Problem.** Tags are mutable: whoever controls (or compromises) the action
repo can repoint `v3`/`v9`/`v1`/`beta` at malicious code that then runs with
this repo's tokens. `@beta` is worse — it *advertises* instability. The repo
already knows the right pattern: `actions/checkout` is SHA-pinned in both
Claude workflows (`claude-code-review.yml:38`, `claude.yml:42`) but tag-pinned
in `main.yml` — the inconsistency shows this is drift, not policy. (Since the
audit, Dependabot has bumped the tags — v2→v3, v8→v9, v5→v7 — which changed
the numbers but not the bug.)

**Solution.** Pin every third-party action to a full commit SHA with the
version as a comment, and let Dependabot's `github-actions` ecosystem keep the
SHAs fresh (it understands SHA pins and updates the comment):

```yaml
- uses: dependabot/fetch-metadata@<full-40-char-sha> # v3.x.y
- uses: actions/github-script@<full-40-char-sha>     # v9.x.y
- uses: actions/checkout@<full-40-char-sha>          # v7.x.y
- uses: ruby/setup-ruby@<full-40-char-sha>           # v1.x.y
- uses: anthropics/claude-code-action@<full-40-char-sha> # pinned release, not @beta
```

Resolve each SHA from the tag at fix time (`git ls-remote <repo> <tag>`).
For `claude-code-action`, move off `@beta` to the latest tagged release and
SHA-pin that. Optionally enforce with `actionlint` or a
`pin-github-action`-style check in CI so new workflows can't reintroduce tags.

### RT-20 — Merge gating depends entirely on out-of-repo branch-protection settings

- **Sources:** #115 §F (🟡)
- **Location:** `.github/workflows/main.yml` (the only test workflow; nothing
  marks it required), referenced by RT-18's auto-merge

**Problem.** Whether the Ruby build blocks *anything* — Dependabot auto-merge
above all — depends on branch-protection settings that live only in the GitHub
UI, invisible to and unversioned by the repo. If protection was never enabled,
or is loosened later, nothing in the codebase records or restores the intent;
auto-merge then merges red PRs.

**Solution.** Codify the protection so it is reviewable and restorable:

- **Preferred: a GitHub ruleset exported into the repo.** Settings → Rules →
  export the ruleset JSON into `.github/rulesets/main.json` requiring: PRs for
  `main`, required status check `build (3.4.7)` (the `Ruby ${{ matrix.ruby }}`
  job — rename it to a stable `test` name first so matrix changes don't break
  the requirement), and no force pushes. Re-import on drift; note the
  export/import procedure in `CONTRIBUTING.md`.
- **Alternative:** the Probot `settings` app (`.github/settings.yml`) with a
  `branches: [main]` protection block, if installing an app is acceptable.
- Minimum bar if neither lands: document the exact required-check
  configuration in `CONTRIBUTING.md` so at least the intended state is
  written down, and add the `needs:`/required-check dependency note to
  `dependabot-automerge.yml` as a comment.

Pairs with RT-18: auto-merge is only as safe as this gate.

### RT-21 — `removeLabel` step lacks `issues: write`; the 403 is swallowed as "label not found"

- **Sources:** #115 §F (🟡)
- **Location:** `.github/workflows/claude-code-review.yml:30-34`
  (`issues: read`), `:79-94` (removeLabel with catch-all)

**Problem.** The job's permission block grants only `issues: read`, so
`github.rest.issues.removeLabel` returns 403 every time. The `catch` logs
"Label not found or already removed" for *any* error, so the failure is
invisible. Consequence: the `claude-review` label is never removed, and the
`synchronize` trigger condition (`:28`) re-runs a full Claude review on every
push to a labeled PR — burning API quota and CI minutes indefinitely.

**Solution.**

```yaml
permissions:
  contents: read
  pull-requests: read
  issues: write        # was: read — removeLabel needs write
  id-token: write
```

and make the catch honest — 404 is the only expected error:

```javascript
try {
  await github.rest.issues.removeLabel({ owner: context.repo.owner,
    repo: context.repo.repo, issue_number: context.issue.number,
    name: 'claude-review' });
} catch (error) {
  if (error.status === 404) {
    console.log('Label not found or already removed');
  } else {
    throw error;  // surface 403s and anything else as a step failure
  }
}
```

**Regression check.** Label a test PR `claude-review`, push a commit: the
review runs once and the label is gone afterwards; the workflow log shows the
removal succeeding.

### RT-22 — CI matrix tests only Ruby 3.4.7 while the gemspec advertises `>= 3.2.0`

- **Sources:** #115 §F (⚪, "additional CI note")
- **Location:** `.github/workflows/main.yml:16-17`; `rodauth-tools.gemspec:34`

**Problem.** The gem claims support for Ruby 3.2+, but CI exercises only
3.4.7. A 3.2/3.3-only breakage (syntax adopted early, stdlib default-gem
changes — the repo already dodged one such issue with the `Set` autoload note
in `table_guard.rb:465-469`) ships undetected.

**Solution.** Either test what is claimed or claim what is tested:

```yaml
strategy:
  matrix:
    ruby: ['3.2', '3.3', '3.4']
```

(Bare minor versions let `ruby/setup-ruby` track patch releases.) If the
maintainer would rather not support older rubies for an experimental project,
raise the gemspec floor to `>= 3.4` instead — the bug is the *mismatch*, and
either edit closes it. Given `CLAUDE.md` calls this a reference
implementation, testing the documented floor is the better look.

---

## Group 7: Console helpers

### RT-23 — `create_tables!` forwards a possibly-nil `db`, crashing with a bare `NoMethodError`

- **Sources:** #115 §F (⚪) — previously the one unchecked item; **now verified
  unresolved**
- **Location:** `lib/rodauth/tools/console_helpers.rb:45-47` (`db` may return
  nil), `:95` (`generator.execute_creates(db)`); aggravated by
  `lib/rodauth/tools/migration.rb:69-94` (`execute_create_tables` assigns
  `@db = db` unconditionally, clobbering a valid mock with nil)

**Problem.** `ConsoleHelpers#db` returns `rodauth.db if rodauth.respond_to?(:db)`
— nil when the console's Rodauth instance has no database. `create_tables!`
passes that nil straight into `SequelGenerator#execute_creates`, which passes
it to `Migration#execute_create_tables`, which *overwrites* the generator's
valid mock DB with nil (`@db = db`) before rendering templates. The user gets
`NoMethodError: undefined method 'database_type' for nil` from deep inside ERB
rendering instead of "you don't have a database connected". Dev-REPL only, but
it's the advertised console workflow (`help` lists `create_tables!`).

**Solution.** Guard at the console boundary with a clear message, and stop
`execute_create_tables` from accepting nil at all:

```ruby
# console_helpers.rb#create_tables!
def create_tables!
  puts "\n=== Creating Missing Tables ==="
  if db.nil?
    puts '✗ No database connection: your `rodauth` instance must be configured with `db DB`.'
    return
  end
  ...
end
```

```ruby
# migration.rb#execute_create_tables
def execute_create_tables(db)
  raise ArgumentError, 'execute_create_tables requires a Sequel::Database (got nil)' if db.nil?

  @db = db
  ...
end
```

The second guard also protects the table_guard `:create`/`:sync` paths if a
nil `db` ever reaches them, and honors the raise-early principle the audit
applied everywhere else.

**Regression tests.** Console helper with a db-less rodauth instance: friendly
message, no exception. `Migration#execute_create_tables(nil)` raises
`ArgumentError` with the clear message.

---

## Suggested fix sequencing

Ordering by risk-reduction per unit of effort, folding in #115's and #116's own
sequencing advice:

1. **RT-09 + RT-08** — `:recreate`/`:drop` correctness (route through
   `execute_drops`, FK order, transaction). Pure bug fix, no
   documented-behavior reversal; #116 explicitly sequences it first.
2. **RT-03 + RT-10** — destructive gating (exact-match allowlist + opt-in +
   blast-radius doc/gate). Needs the maintainer's option (a)/(b) ruling since
   it reverses #24-documented behavior.
3. **RT-04 + RT-17 + RT-11** — the fail-open family (table existence, column
   verification, discovery errors). One principle — never report "verified" over
   an unverified set — applied in three places.
4. **RT-01 + RT-02** — secret-guard detection (shared `production_env?`) and
   ENV single-consumer fix; RT-01's detector is then reused by RT-03.
5. **RT-18 + RT-21 + RT-19 + RT-20** — CI/supply-chain batch (drop
   self-approval, fix label permissions, SHA-pin, codify protection). All four
   are workflow-file-only changes; land as one PR.
6. **RT-16 + RT-14 + RT-13 + RT-15** — identifier/codegen hardening batch
   (anchors, `.inspect` emission + registration validation, prefix validation,
   Proc-default rejection). Mutually reinforcing; one PR.
7. **RT-05, RT-06, RT-07, RT-12, RT-22, RT-23** — remaining ergonomics and
   robustness items; each is small and independent.

Structural opportunities from #115 that these fixes advance: (b) validated
symbols + `.inspect` emission is the incremental step toward replacing
string-built migrations with DSL calls (RT-13/14); (c) the shared exact-match
multi-var production detector lands via RT-01 and is consumed by RT-03; (d)
each RT section above names the spec that covers its previously-untested
danger path.
