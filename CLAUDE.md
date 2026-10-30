# LaunchVPN Client

Android and iOS Flutter Xray-core client, a fork of OneXray.
[Current contracts](docs/README.md) describe shipped behavior; Git history holds
retired plans and progress logs.

Docs we write in this public repo are in English, including over the language
rule in `docs/AGENTS.md`.

## Engineering rules

- Dependencies flow `pages → service → core`. Services own business logic;
  custom page controllers extend `PageCubit` and expose Bloc state.
  Text, scroll, focus and third-party controllers remain UI resources.
- Our screens live in `lib/brand/`. Leave `lib/pages/` as upstream has it.
- Keep `lib/service/`, `lib/core/`, `swift/` and the Android tunnel close to
  upstream. Make the core changes we need as small, separate commits.
- Keep typography and colors in the shared brand theme, out of individual
  screens. UI-only changes preserve behavior and data contracts.
- Verify dependency maintenance and SDK/platform compatibility before adoption:
  archive status, dated releases, substantive commits and maintainer responses.
- Pin `LIBXRAY_REF` in our CI to a commit, never `main`, and bump it only together
  with an upstream merge.
- Edit source models, ARB, Pigeon and FFI definitions, then regenerate outputs.
  Generated Dart, Kotlin, Swift, Drift, FFI and localization files are not sources.

## Read for the task

- Startup, permissions, navigation or UI: [App behavior](docs/app.md).
- Configuration, validation, connection lifecycle, native VPN or traffic:
  [Xray configuration](docs/xray-configuration.md).
- Database, Geodata, queues, updates or cleanup: [data management](docs/data-management.md).
- Import, subscriptions, age or sharing: [servers and sharing](docs/subscriptions-and-sharing.md).
- Backup protocol, restore or cloud storage: [backup](docs/backup.md).
- Local HTTP API, Android broadcasts or command authorization:
  [external interfaces](docs/external-interfaces.md).
- Packaging, signing or CI releases: [build scripts](build_scripts/README.md).
  Apple/Android release commands may upload to stores; they are not local checks.
- Native bridge changes: inspect `pigeon/message.dart`, `lib/core/pigeon/` and the
  Swift/Kotlin consumers.

## Agent skills

### Issue tracker

Issues live in Jira, project `LVPN`, not GitHub. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary, as Jira labels: `needs-triage`, `needs-info`,
`ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: read `CONTEXT.md` at the root and use its vocabulary. See
`docs/agents/domain.md`, with one exception: ADRs are private and not part of
this public repo. Never create `docs/adr/` or commit ADRs here; raise decisions
worth recording with the user instead.

## Verification

All Flutter/Dart commands run serially across terminals and agents because
`.dart_tool` and native build state are shared. Use [verification](docs/validation.md)
for scenario selection, checks and platform-specific acceptance.

- Android emulator validation may start VPN. On macOS, do not start VPN or take
  screenshots.
- Keep demos, fixtures and evidence outside the repo, with isolated data and
  minimal setup; never validate against the developer's main database.
- Match checks to the change and run `git diff --check`. Documentation-only work
  needs path/link checks, not App tests. Report static, automated, device and
  release results separately. Commit, push and PR actions require user authority.
