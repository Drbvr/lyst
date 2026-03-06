# ListApp iOS UI Scaffolding

SwiftUI views and mock data for the List Management iOS app.

## Quick Start

```bash
open ListApp.xcodeproj
```

1. Select the **ListApp** scheme in the toolbar
2. Choose an iPhone simulator (e.g. iPhone 16)
3. Press **Cmd+R** to build and run

The Xcode project references the `Core` SPM package as a local dependency — no additional setup needed.

## Directory Structure

```
ListApp/
├── App/ListAppApp.swift          # @main entry point
├── ViewModels/AppState.swift     # Central app state (uses Core engine)
├── Views/
│   ├── ContentView.swift         # TabView with 5 tabs
│   ├── SavedViewsListView.swift  # Saved views list
│   ├── ItemListView.swift        # Item list with swipe actions
│   ├── ItemDetailView.swift      # Item detail (properties, tags, metadata)
│   ├── FilterView.swift          # Custom filter builder
│   ├── TagBrowserView.swift      # Hierarchical tag browser
│   ├── SearchView.swift          # Full-text search
│   └── SettingsView.swift        # Settings (stubs)
├── Components/
│   ├── ItemRowView.swift         # Reusable item row
│   ├── TagChipView.swift         # Tag chip
│   └── FlowLayout.swift          # Flow layout for tags
└── Services/
    └── FileSystemManager.swift   # File system stub (mock data)
```

## Architecture

- **@Observable** pattern (iOS 17+) for state management
- **AppState** wraps Core's `ItemFilterEngine`, `FullTextSearchEngine`, and `TagHierarchy`
- All models come from `Core` — no duplicated types
- Mock data via `Core.MockData` for development/previews
- `FileSystemManager` is a stub ready for real iCloud Drive integration
