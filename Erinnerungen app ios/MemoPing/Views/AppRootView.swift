import SwiftUI

enum RemindlyStyle {
    static let ink = Color(red: 0.02, green: 0.02, blue: 0.04)
    static let surface = Color(red: 0.08, green: 0.08, blue: 0.12)
    static let surfaceRaised = Color(red: 0.12, green: 0.11, blue: 0.18)
    static let accent = Color(red: 0.58, green: 0.38, blue: 1.0)
    static let cyan = Color(red: 0.18, green: 0.73, blue: 1.0)
    static let pink = Color(red: 1.0, green: 0.24, blue: 0.58)
    static let orange = Color(red: 1.0, green: 0.55, blue: 0.22)
    static let success = Color(red: 0.25, green: 0.88, blue: 0.46)
    static let warning = Color(red: 1.0, green: 0.78, blue: 0.30)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.42)

    static let cardRadius: CGFloat = 26
    static let controlRadius: CGFloat = 18
    static let pillRadius: CGFloat = 16

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.015, green: 0.016, blue: 0.028),
                Color(red: 0.045, green: 0.035, blue: 0.075),
                Color(red: 0.015, green: 0.018, blue: 0.032)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [cyan, accent, pink],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var warmGradient: LinearGradient {
        LinearGradient(
            colors: [orange, pink, accent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var quietGradient: LinearGradient {
        LinearGradient(
            colors: [
                surfaceRaised.opacity(0.92),
                surface.opacity(0.88)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var cardFill: Color {
        Color.white.opacity(0.085)
    }

    static var elevatedFill: Color {
        Color.white.opacity(0.13)
    }

    static var border: Color {
        Color.white.opacity(0.14)
    }

    static var mutedText: Color {
        Color.white.opacity(0.64)
    }

    static var faintText: Color {
        Color.white.opacity(0.42)
    }

    static func tintedCardGradient(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                tint.opacity(0.18),
                surfaceRaised.opacity(0.92),
                surface.opacity(0.94)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static func iconFill(_ tint: Color) -> LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.95), tint.opacity(0.42)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

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
        .tint(RemindlyStyle.accent)
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AppRootView()
        .modelContainer(for: [MemoItem.self, MemoCategoryItem.self], inMemory: true)
}
