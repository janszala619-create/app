import SwiftData
import SwiftUI

@main
struct MemoPingApp: App {
    private let modelContainer: ModelContainer = {
        let schema = Schema([MemoItem.self])

        do {
            let configuration = ModelConfiguration(schema: schema)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("MemoPing: ModelContainer konnte nicht erstellt werden: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(modelContainer)
    }
}
