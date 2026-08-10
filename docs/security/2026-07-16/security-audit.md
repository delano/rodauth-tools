# Security & Bug Sweep — 2026-07-16

**Scope:** Routine automated sweep of `rodauth-tools` for hardcoded secrets,
weak crypto, injection risks, unsafe deserialization, insecure auth flows,
and high-impact data-loss/race bugs. No dependency-vulnerability scanning
(handled by Renovate/Dependabot).

**Prior audit on record:** [`docs/unresolved-bugs.md`](../../unresolved-bugs.md)
(verified against `main` @ `a600397`, 2026-07-05) is a comprehensive,
line-verified audit of 23 distinct bugs (RT-01 – RT-23) covering secret
guards, `table_guard`, table discovery, migration codegen, `external_identity`,
CI/supply-chain, and console helpers. This sweep does not restate that
document's findings — see it directly for full detail, root cause, and
proposed fixes on every open item.

## What changed since the last audit

Only one substantive code change landed between `a600397` and `HEAD`
(`a93a53f`): commit `635fec7` ("Fix :recreate/:drop to include hidden tables
and run atomically"). Verified by reading the diff directly:

- **RT-09** (`:recreate`/`:drop` missing hidden tables) — **fixed**. Both
  modes now route drops through `SequelGenerator#execute_drops` with an
  explicit `features:` enumeration, which pulls the full ERB-template table
  list (hidden tables included) instead of the `*_table`-method-derived list.
- **RT-08** (unordered, untransacted drops) — **fixed**. The drop+create
  cycle is wrapped in one `db.transaction`; the FK-agnostic `drop_tables`
  helper is now used only for the independent `schema_info`/`schema_migrations`
  tables, which have no ordering constraints.

Everything else in `docs/unresolved-bugs.md` (RT-01 – RT-07, RT-10 – RT-23)
remains open, unchanged from the prior verification. All other commits since
`a600397` are Dependabot dependency bumps (sequel, tilt, rubocop, websocket-driver).

## New areas reviewed this pass

Reviewed code and configuration not covered in depth by the prior audit; no
new findings surfaced:

- **`lib/rodauth/tools/account_id_cipher.rb`** — 4-round Feistel/HMAC-SHA256
  format-preserving cipher. Construction, key-length floor (32 bytes),
  canonical-token rejection on decode, and the documented birthday-bound
  caveat (~2^16 tokens/secret) all check out as implemented and honestly
  disclosed in the class docstring. No issue.
- **`lib/rodauth/features/account_id_obfuscation.rb`** — email-token and
  remember-cookie obfuscation wrapper. Its `production_env_check` default
  (`ENV.fetch('RACK_ENV', 'production') == 'production'`) has the same
  exact-match fragility as `hmac_secret_guard`/`jwt_secret_guard` — this is
  already tracked under **RT-01**, which explicitly names this file as
  sharing the pattern and proposes a shared fix. No new issue; flagging here
  only to confirm it was checked, not missed.
- **CI workflows** (`.github/workflows/*.yml`) — current file contents match
  the state RT-18/RT-19/RT-20/RT-21/RT-22 already describe; no drift.
  `dependabot-automerge.yml` still auto-approves + auto-merges patch/minor
  updates with the bot's own token and no required-check dependency (RT-18).
- Repo-wide sweep for common anti-patterns (`eval`, `instance_eval`, `send`/
  `__send__`, `system`, `Marshal.load`, `YAML.load`, MD5/SHA1 usage) turned up
  only the call sites already documented in RT-13/RT-14 (migration `eval`,
  identifier interpolation) and ordinary internal metaprogramming (`.send`
  with hardcoded, non-user-controlled method names for dynamic method
  definition/dispatch — not an injection vector).

## Findings

None new. No action items beyond what `docs/unresolved-bugs.md` already
tracks.

For reference, the highest-severity items still open there and worth
prioritizing when bandwidth allows:

| ID | Sev | Title |
|---|---|---|
| RT-01 | 🔴* | Production detection is a brittle exact match (secret guards + account_id_obfuscation) |
| RT-03 | 🟠 | Destructive `table_guard` modes gated by prefix match, no opt-in |
| RT-04 | 🟠 | `table_exists?` fails open on DB errors |
| RT-18 | 🟠 | Dependabot auto-merge + self-approval, no enforced CI gate |

See `docs/unresolved-bugs.md` for full detail and proposed fixes on each.
