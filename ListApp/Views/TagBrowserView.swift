import SwiftUI
import Core

struct TagBrowserView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            ForEach(appState.tagGroups, id: \.tag) { group in
                if group.children.isEmpty {
                    // Flat tag — no subtags: navigate directly, no dropdown needed
                    NavigationLink {
                        ItemListView(
                            title: "#\(group.tag)",
                            items: appState.items.filter { $0.tags.contains(group.tag) },
                            displayStyle: .list
                        )
                    } label: {
                        HStack {
                            Image(systemName: "tag")
                                .foregroundColor(.accentColor)
                            TagChipView(tag: group.tag)
                            Spacer()
                            Text("\(group.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                } else {
                    // Has subtags: show expandable group
                    DisclosureGroup {
                        // "All under this tag" row first
                        NavigationLink {
                            ItemListView(
                                title: "#\(group.tag) (all)",
                                items: appState.items.filter { item in
                                    item.tags.contains { $0.hasPrefix(group.tag) }
                                },
                                displayStyle: .list
                            )
                        } label: {
                            HStack {
                                Text("All in #\(group.tag)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(group.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Individual subtags
                        ForEach(group.children, id: \.tag) { child in
                            NavigationLink {
                                ItemListView(
                                    title: "#\(child.tag)",
                                    items: appState.items.filter { $0.tags.contains(child.tag) },
                                    displayStyle: .list
                                )
                            } label: {
                                HStack {
                                    TagChipView(tag: child.tag)
                                    Spacer()
                                    Text("\(child.count)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.accentColor)
                            Text(group.tag)
                                .font(.headline)
                            Spacer()
                            Text("\(group.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .navigationTitle("Tags")
    }
}
