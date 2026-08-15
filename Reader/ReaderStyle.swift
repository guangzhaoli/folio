import AppKit

struct ReaderStyle: Sendable {
    var bodyPointSize: CGFloat
    var measure: CGFloat
    var lineHeight: CGFloat
    var listStep: CGFloat

    static let `default` = ReaderStyle(
        bodyPointSize: 17,
        measure: 780,
        lineHeight: 1.32,
        listStep: 24
    )

    func headingPointSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 28
        case 2: return 22
        case 3: return 19
        case 4: return 17
        default: return 16
        }
    }

    func headingSpaceBefore(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 6
        case 2: return 22
        case 3: return 18
        default: return 14
        }
    }

    func headingSpaceAfter(_ level: Int) -> CGFloat {
        level == 1 ? 10 : 8
    }
}
