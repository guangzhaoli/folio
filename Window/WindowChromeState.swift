import Foundation

enum ViewMode: Int, CaseIterable {
    case source = 0
    case split = 1
    case reading = 2

    static var stored: ViewMode {
        if UserDefaults.standard.object(forKey: "folio.viewMode") == nil { return .split }
        return ViewMode(rawValue: UserDefaults.standard.integer(forKey: "folio.viewMode")) ?? .split
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: "folio.viewMode")
    }
}
