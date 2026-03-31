# Setup Guide

One-time and per-extension setup steps that live **outside the codebase** in Apple Developer Portal and Xcode Cloud. Nothing here is automated — these are manual UI steps that must be completed before Xcode Cloud can sign and distribute the app.

---

## Apple Developer Portal — Initial Setup

> URL: [developer.apple.com/account](https://developer.apple.com/account) → Certificates, Identifiers & Profiles

### 1. Register App IDs

Register two explicit App IDs (if not already present):

| Description | Bundle ID |
|---|---|
| ListApp | `com.bvanriessen.listapp` |
| ListApp Share Extension | `com.bvanriessen.listapp.ShareExtension` |

Steps: **Identifiers → +** → App IDs → App → Continue → fill in description + explicit bundle ID → Continue → Register.

### 2. Register the App Group

**Identifiers → +** → App Groups → Continue → Description: `ListApp Group`, Identifier: `group.com.bvanriessen.listapp` → Continue → Register.

### 3. Enable App Groups on both App IDs

For **each** of the two App IDs above:
1. Click the App ID to edit it
2. Check **App Groups** under Capabilities
3. Click **Configure** next to App Groups → select `group.com.bvanriessen.listapp`
4. Save

---

## Apple Developer Portal — Adding a New Extension or Target

Every new app extension (Share, Widget, Notification Service, Intents, etc.) needs its own App ID. Do this **before** merging the PR that adds the extension.

- [ ] Register new App ID: `com.bvanriessen.listapp.<ExtensionName>` (Explicit)
- [ ] If the extension shares data with the main app via App Groups: enable **App Groups** on the new App ID and assign `group.com.bvanriessen.listapp`
- [ ] Verify the matching code-side checklist in `CLAUDE.md → Adding a New Target or App Extension`

---

## Xcode Cloud — Workflow Configuration

> App Store Connect → Xcode Cloud → Workflows → Default → Edit

### Required settings

| Setting | Value |
|---|---|
| Environment → Xcode version | 16.x or later |
| Archive → Scheme | ListApp |
| Post-Actions → TestFlight Internal Testing | must be configured (see below) |

### Connecting App Store Connect for TestFlight

Xcode Cloud's TestFlight post-action requires your App Store Connect team to be linked:

1. In App Store Connect, go to **Xcode Cloud → Settings**
2. Under **App Store Connect API**, confirm an API key is connected (or generate one under **Users and Access → Integrations → App Store Connect API**)
3. Back in the workflow, open **Post-Actions → TestFlight Internal Testing**
4. Select your App Store Connect team in the account picker
5. Save the workflow

If this is not configured, builds will succeed but fail at "Preparing build for App Store Connect" with an authentication error (`DVTServicesSessionProviderCredentialITunesAuthenticationContextError Code=1`).

### Fixing a stale session credential

If the workflow was previously working and the error reappears (especially after editing workflow settings or reconnecting your Apple ID in Xcode), the `DVTServicesSessionProviderCredential` session link between Xcode Cloud and App Store Connect may have been invalidated. The fix is to **delete and recreate the workflow**:

1. App Store Connect → Xcode Cloud → Workflows → select the workflow → **Delete**
2. Create a new workflow with the same settings:
   - Start Condition: Branch Changes → `main`
   - Action: Archive — iOS, Scheme: `ListApp`
   - Distribution: TestFlight (Internal Testing Only)
   - Post-Action: TestFlight Internal Testing → Group: BVR
3. Save — this re-establishes a fresh session credential

Reconnecting your Apple ID in Xcode → Preferences → Accounts does **not** fix this; only recreating the workflow does.

---

## Running Tests Locally

```bash
# Run all CoreTests (231 tests)
swift test

# Run a single test suite
swift test --filter FilterEngineTests

# Run a single test case
swift test --filter FilterEngineTests/testTagFilter
```

Tests also run automatically on every PR via GitHub Actions (`Swift Tests` check). PRs cannot be merged until the check passes.
