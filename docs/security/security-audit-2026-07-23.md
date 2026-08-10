# Security & Bug Audit — 2026-07-23

- **Scope:** `rodauth-tools` (primary), plus a lighter cross-repo sweep of the
  other Delano/OneTimeSecret repos this account has access to
  (`onetimesecret/onetimesecret`, `delano/familia`, `delano/otto`,
  `onetimesecret/rodauth`, `onetimesecret/rodauth-oauth`,
  `onetimesecret/rodauth-omniauth`, `onetimesecret/omniauth`).
- **Method:** Manual review — diffed each repo against its last-known audit
  baseline (or, where none existed, against its recent commit history),
  re-verified prior findings that touched changed code, and grep-scanned for
  common anti-patterns (hardcoded secrets, `eval`/`Marshal.load`/unsafe
  `YAML.load`, string-interpolated SQL/shell, weak crypto).
- **Prior audit referenced:** `docs/unresolved-bugs.md` (2026-07-05, verified
  against `main@a600397`, 23 unresolved items RT-01–RT-23).

## Bottom line

No new Critical/High findings in this pass, in this repo or the others
checked. One item from the prior audit has since been fixed; everything else
in `docs/unresolved-bugs.md` is unchanged and still stands as written there —
see that file for full descriptions, failure scenarios, and recommended
fixes. This report only records the *delta* since 2026-07-05, per the
"don't repeat the same audit" guidance in `CLAUDE.md`.

## Delta since 2026-07-05 (`a600397` → `a663f72`)

Only two files changed in `lib/`: `table_guard.rb` and `sequel_generator.rb`,
both in commit `635fec7` ("Fix :recreate/:drop to include hidden tables and
run atomically").

- **RT-08 (drop ordering / no transaction) — fixed.** `:recreate` and `:drop`
  now route through `SequelGenerator#execute_drops`, and the whole drop+create
  cycle is wrapped in `db.transaction do ... end` (`table_guard.rb:723-736`,
  `:751-764`). Verified: PostgreSQL/SQLite now roll back atomically on a
  mid-cycle failure; MySQL's auto-commit-DDL limitation is called out
  correctly in a comment rather than silently assumed away.
- **RT-09 (`:recreate`/`:drop` miss hidden tables) — fixed.** Both modes now
  enumerate tables via `enabled_template_features` +
  `execute_drops(db, features:)`, which walks the ERB templates (including
  the hidden `account_statuses`/`account_password_hashes` tables) instead of
  the discovered `*_table` method list. Verified against the failure mode
  described in RT-09 (stale `account_statuses` blocking recreate) — the new
  code path no longer has that gap. A regression spec
  (`spec/.../table_guard_destructive_modes_spec.rb`) was added covering
  `:recreate` over a pre-existing schema, `:drop` removing hidden tables, and
  transactional rollback.

**Everything else is unchanged and still open**, spot-checked directly
against current `main`:

- RT-01 (production-env detection still an exact `== 'production'` match,
  `hmac_secret_guard.rb:74`, `jwt_secret_guard.rb:74`)
- RT-03 (destructive-mode gate is still the `start_with?` prefix match against
  only `RACK_ENV`, `table_guard.rb:679,696,742`, no `table_guard_allow_destructive`
  opt-in)
- RT-04 (`table_exists?` still fails open on DB errors, `table_guard.rb:282-284`,
  comment literally says "Assume exists to avoid false positives")
- RT-02, RT-05–RT-07, RT-10–RT-23: not touched by any commit since the last
  audit; still as documented.

No new issues were found in `table_guard.rb`/`sequel_generator.rb` beyond
what RT-08/RT-09 already covered — the fix is a clean, well-tested
implementation of the documented solution.

## Cross-repo sweep (informational, no filed reports)

- **`onetimesecret/onetimesecret`** — already has its own audit trail
  (`docs/security/security-audit-2026-07-19.md`). Confirmed the security
  fixes that landed after that doc's stated content (#3837 TLS-proxy/session
  cookie, #3841 canonical-domain guard, #3810 session-watermark rotation) all
  merged *before* the audit doc's own commit timestamp (2026-07-22), so
  they're within its stated coverage — no gap. Commits since then
  (`e615ed74..HEAD`) are documentation-only (a design-system readiness
  audit), no application code changed. Nothing to add.
- **`delano/otto`** — active recent work hardening geo-IP header trust
  (`lib/otto/privacy/geo_resolver.rb`, `ip_privacy_middleware.rb`): geo
  headers are only trusted when the request's `REMOTE_ADDR` matches a
  configured trusted-proxy CIDR (default: no proxies configured → headers
  never trusted, fails closed), country-code parsing uses `\A`/`\z` anchors
  (not `^`/`$`), and the maintainer's own commit history shows this already
  went through an adversarial review pass (`3cdad03`, `0098be6`). Reviewed
  independently and found no gaps beyond what that pass already fixed.
- **`delano/familia`, `onetimesecret/rodauth`, `onetimesecret/rodauth-oauth`,
  `onetimesecret/rodauth-omniauth`, `onetimesecret/omniauth`** — no commits
  in the last two weeks. Pattern grep for hardcoded secrets, `eval`,
  `Marshal.load`, unsafe `YAML.load`, and raw SQL/shell interpolation turned
  up nothing beyond developer-config-only string interpolation (e.g.
  `rodauth`'s upstream `migrations.rb` SQL-function templates, which
  interpolate `table_name`/`search_path` set by the integrating app itself,
  not end-user input — same trust boundary already documented for this
  repo's own migration generator in RT-13–RT-15).

## Not re-litigated

Per `CLAUDE.md`, dependency version findings are explicitly out of scope
(Renovate/Dependabot own that). No new tickets were opened; see
`docs/unresolved-bugs.md` for the existing RT-01…RT-23 backlog and its
suggested fix sequencing.
