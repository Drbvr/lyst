# Development Guidelines

## Git Workflow

### Before creating any branch
1. **Always `git fetch origin` first** — never skip this step.
2. **Check what branches are already merged — these must never be reused:**
   ```bash
   git branch -r --merged origin/main
   ```
   Any branch appearing here is already merged. Creating or pushing to it produces a
   stale / diverged branch and is a recurring source of bugs. Choose a new name.
3. **Verify the new branch name doesn't already exist remotely:**
   ```bash
   git branch -r | grep <branch-name>
   ```
4. **Branch off latest `main`:**
   ```bash
   git checkout main && git pull origin main
   git checkout -b fix/<short-description>    # or feat/<short-description>
   ```

> **Automated guard:** `.githooks/pre-push` blocks pushes to any branch already merged
> into `origin/main`. Run `bash scripts/setup-hooks.sh` once after cloning to activate.

### Committing
- Commit per logical unit (one commit per bug fix or feature is fine within a branch).
- Write clear, descriptive commit messages explaining *what* and *why*.

### Bundling work
- **Bundle related fixes into a single feature branch and PR.** Don't open one PR per tiny fix.
- If bugs are logically unrelated, use separate branches/PRs.

### Before pushing / opening a PR
- **Run Swift tests** before pushing:
  ```bash
  swift test
  ```
- **Run the project-file verification script** before every push:
  ```bash
  bash scripts/verify-project-files.sh
  ```
  This catches Swift files that exist on disk but are missing from `project.pbxproj`,
  which causes "Cannot find X in scope" errors in Xcode Cloud. Any new `.swift` file
  added to `ListApp/` **must** also be registered in the Xcode project.
- The same check runs automatically via GitHub Actions on every PR targeting `main`.
  The PR cannot be merged until this check passes.

### Pushing and PRs
- Always push with: `git push -u origin <branch-name>`
- **Never push directly to `main`** — always use a feature branch + PR.
- After a PR is merged, do not reuse that branch for new work. Start fresh off `main`.

### Branch naming
| Purpose | Pattern |
|---|---|
| Bug fixes | `fix/<short-description>` |
| New features | `feat/<short-description>` |
| Hotfixes | `hotfix/<short-description>` |

## First-time Setup (after cloning)

```bash
bash scripts/setup-hooks.sh   # installs the pre-push merged-branch guard
```

## Adding a New Target or App Extension

> **Before writing any code**, complete the Apple Developer Portal steps in `SETUP.md → Adding a New Extension or Target`. Xcode Cloud cannot sign or export a target whose App ID is not registered in the portal.

Code-side checklist:
- Set `DEVELOPMENT_TEAM = S43L28SVX2;` in the new target's **Debug and Release** build configs in `project.pbxproj`
- Add a `.entitlements` file if the extension shares data via App Groups
- Register all new `.swift` source files in `project.pbxproj` (same rule as existing targets — run `bash scripts/verify-project-files.sh` to verify)

## Xcode Cloud & App Store Connect

Xcode Cloud workflow settings — App Store Connect credentials, TestFlight post-action, and distribution methods — are configured in **App Store Connect → Xcode Cloud → Workflows**, not in the codebase. See `SETUP.md → Xcode Cloud Workflow Configuration` for required settings.

If a build fails with "Preparing build for App Store Connect failed", the TestFlight post-action is missing App Store Connect credentials (a portal-only fix).

## Project Structure
- `ListApp/` — iOS app (SwiftUI, @Observable)
- `Sources/Core/` — shared logic (models, parsers, filter engine)
- `ListApp/ViewModels/AppState.swift` — central observable state
- `ListApp/Views/` — all SwiftUI views
- `ListApp/Services/FileSystemManager.swift` — file I/O for the app layer
- `Sources/Core/Parsers/MarkdownParser.swift` — markdown/YAML item parsing
