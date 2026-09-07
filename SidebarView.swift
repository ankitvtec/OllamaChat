import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var store: ConversationStore
    @AppStorage("model") private var model = "qwen3.8-vision"
    @State private var showSettings = false

    var body: some View {
        List {
            Section {
                Button {
                    store.newConversation(model: model)
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
            }

            Section("Conversations") {
                ForEach(store.conversations) { conversation in
                    Button {
                        store.selectedID = conversation.id
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(conversation.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(conversation.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(
                        store.selectedID == conversation.id
                            ? Color.claudeAccent.opacity(0.15)
                            : nil
                    )
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.delete(store.conversations[index].id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    showSettings = true
                } label: {
                    Label("Server Settings", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}
