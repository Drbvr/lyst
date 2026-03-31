# Development Guidelines

## Git Workflow

### Before creating any branch
1. **Always `git fetch origin` first** — never skip this step.
2. **Verify the branch doesn't already exist remotely:**
   ```bash
   git branch -r | grep <branch-name>
   ```
   Never reuse a branch that already exists on the remote — it may already be merged or stale.
3. **Branch off latest `main`:**
   ```bash
   git checkout main && git pull origin main
   git checkout -b fix/<short-description>    # or feat/<short-description>
   ```

### Committing
- Commit per logical unit (one commit per bug fix or feature is fine within a branch).
- Write clear, descriptive commit messages explaining *what* and *why*.

### Bundling work
- **Bundle related fixes into a single feature branch and PR.** Don't open one PR per tiny fix.
- If bugs are logically unrelated, use separate branches/PRs.

### Before pushing / opening a PR
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

## Project Structure
- `ListApp/` — iOS app (SwiftUI, @Observable)
- `Sources/Core/` — shared logic (models, parsers, filter engine)
- `ListApp/ViewModels/AppState.swift` — central observable state
- `ListApp/Views/` — all SwiftUI views
- `ListApp/Services/FileSystemManager.swift` — file I/O for the app layer
- `Sources/Core/Parsers/MarkdownParser.swift` — markdown/YAML item parsing
