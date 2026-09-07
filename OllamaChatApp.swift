import SwiftUI

@main
struct OllamaChatApp: App {
    @StateObject private var store = ConversationStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var store: ConversationStore
    @AppStorage("serverURL") private var serverURL = "192.168.1.192:11434"
    @AppStorage("model") private var model = "qwen3.8-vision"
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if store.selected != nil {
                ChatView()
                    .navigationDestination(isPresented: $showSettings) {
                        SettingsView()
                    }
            } else {
                ContentUnavailableView(
                    "No Conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Start a new chat to begin.")
                )
            }
        }
        .tint(Color.claudeAccent)
        .onAppear {
            if store.selected == nil {
                store.newConversation(model: model)
            }
        }
    }
}
