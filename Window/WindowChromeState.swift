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

enum OutlinePlacement: String, CaseIterable {
    case belowLibrary
    case top
    case trailing

    static let defaultsKey = "folio.outlinePlacement"
    static let visibleKey = "folio.outlineVisible"

    var title: String {
        switch self {
        case .belowLibrary: return "Below Library"
        case .top: return "Top"
        case .trailing: return "Right"
        }
    }

    static var stored: OutlinePlacement {
        OutlinePlacement(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .belowLibrary
    }

    func persist() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }

    static var isVisible: Bool {
        if UserDefaults.standard.object(forKey: visibleKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: visibleKey)
    }

    static func persistVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: visibleKey)
    }
}
