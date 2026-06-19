import SwiftUI

struct AppRootView: View {
    @StateObject private var captureRequestCenter = CaptureRequestCenter.shared

    var body: some View {
        TabView {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Memos", systemImage: "list.bullet")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Einstellungen", systemImage: "gear")
            }
        }
        .sheet(isPresented: $captureRequestCenter.isCapturePresented) {
            CaptureView {
                captureRequestCenter.isCapturePresented = false
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [MemoItem.self, MemoCategoryItem.self], inMemory: true)
}
