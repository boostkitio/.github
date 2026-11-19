# boostkitio/.github

**Not in use (19 Nov 2026).** Matt chose a free local pre-push hook over per-push Actions to stay inside the organisation's Actions budget; see `_HOME/sops/ci-standard.md`. This workflow is kept for any repo that needs Actions checks on pull requests.

The Boostkit CI standard (Matt, 19 Nov 2026): every repo runs lint, typecheck, test and build on every push to `main` and every pull request.

- `.github/workflows/node-ci.yml`: the reusable workflow. Inputs: `node-version`, `skip`, `build-command`, `test-command`, `env` (dummy, non-secret build-time names only), `working-directory`, `timeout-minutes`.
- `workflow-templates/ci.yml`: the caller each repo copies to `.github/workflows/ci.yml`.
- `scripts/ci.sh`: the steps, shared by CI and local runs. `scripts/local-check.sh <owner/repo> <dir>` pre-flights a repo from a fresh clone before its CI is switched on.

Public on purpose: the org is on GitHub Free, so public and personal-account repos can only call a public reusable workflow. Nothing secret lives here.

Inventory, known gaps and how failures are handled: `_HOME/sops/ci-standard.md` in Matt's home repo.
