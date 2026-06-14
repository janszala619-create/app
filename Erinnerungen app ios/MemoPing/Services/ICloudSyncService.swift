import Foundation

enum ICloudAccountState: Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable(String)

    var displayText: String {
        switch self {
        case .available:
            return "verfügbar"
        case .noAccount:
            return "nicht angemeldet"
        case .restricted:
            return "eingeschränkt"
        case .couldNotDetermine:
            return "unbekannt"
        case .temporarilyUnavailable:
            return "nicht verfügbar"
        }
    }

    var detailText: String {
        switch self {
        case .available:
            return "iCloud ist auf diesem Gerät verfügbar."
        case .noAccount:
            return "Melde dich in den iOS-Einstellungen bei iCloud an, um Memos zu synchronisieren."
        case .restricted:
            return "iCloud ist auf diesem Gerät eingeschränkt."
        case .couldNotDetermine:
            return "Der iCloud-Status konnte gerade nicht ermittelt werden."
        case .temporarilyUnavailable(let message):
            return message
        }
    }
}

final class ICloudSyncService {
    static let shared = ICloudSyncService()

    static var cloudKitContainerIdentifier: String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.example.MemoPing"
        return "iCloud.\(bundleIdentifier)"
    }

    private init() {}

    func accountState() async -> ICloudAccountState {
        .temporarilyUnavailable("Die unsigned IPA läuft stabil mit lokalem Speicher. iCloud-Sync wird erst in einem signierten Xcode-Build mit aktivierten CloudKit-Entitlements geprüft.")
    }
}
