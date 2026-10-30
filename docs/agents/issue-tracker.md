# Issue tracker: Jira

Issues and specs live in Jira, project `LVPN` (https://launchvpn.atlassian.net).
Use the Atlassian MCP tools. Code and PRs live on GitHub in
`LaunchVPN/launchvpn-client`.

Never file issues, PRs or comments into `YuanDevTeam/OneXray`. In a fresh clone,
run `gh repo set-default LaunchVPN/launchvpn-client` before using `gh`.

## Conventions

- Write Jira issue text in plain Russian.
- Write PR titles, descriptions and GitHub comments in English, and reference
  the Jira key (`LVPN-12`) in the PR title or description.
- Use [triage-labels.md](triage-labels.md) for canonical triage roles.
- Issue types: `Эпик`, `История`, `Задание`, `Подзадача`.
- Statuses: `К выполнению`, `В работе`, `Проверка`, `Готово`.

## Reviews and authorization

- For PR reviews, resolve the actual remote base/head and record the commit IDs
  without switching the checkout. Unpushed local changes are not the PR diff.
- For local reviews, use the user's requested fixed point. Follow `code-review`
  for separate Standards and Spec findings with severity, location, impact and evidence.
- Analysis and review are read-only unless the user also authorizes changes or
  publication. They do not authorize code edits, Jira or GitHub comments, label
  changes, closure or pushes.

## Issue operations

- Publish a ticket: `createJiraIssue` in `LVPN`.
- Fetch a ticket: `getJiraIssue`, plus `listJiraIssueComments` for comments.
- List tickets: `searchJiraIssuesUsingJql`, e.g. `project = LVPN AND statusCategory != Done`.
- Comment: `addOrEditJiraIssueComment`.
- Add or remove labels: `editJiraIssue`. Jira creates a label on first use.
- Close: comment with the reason, then `transitionJiraIssue` to `Готово`.
- Parent: set `parent` to the epic's key.
- Blocking: the `Blocks` issue link, found through `discover`. A ticket is
  startable when every blocker is `Готово`.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding operations

Used by `/wayfinder`. The map is one `Эпик` with child issues as tickets.

- Map: label it `wayfinder:map`.
- Child ticket: set `parent` to the map's key.
- Child labels: `wayfinder:research`, `wayfinder:prototype`,
  `wayfinder:grilling`, or `wayfinder:task`.
- Blocking: see Issue operations.
- Frontier: choose the first open, unassigned child in map order without
  an open blocker.
- Claim: assign the ticket to yourself with `editJiraIssue`.
- Resolve: comment with the answer, move the child to `Готово`, then add a
  context pointer to the map's Decisions-so-far.
