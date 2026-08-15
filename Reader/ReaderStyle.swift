import AppKit

struct ReaderStyle: Sendable {
    var bodyPointSize: CGFloat
    var measure: CGFloat

    static let `default` = ReaderStyle(bodyPointSize: 17, measure: 680)

    func headingPointSize(_ level: Int) -> CGFloat {
        switch level {
        case 1: return bodyPointSize + 11
        case 2: return bodyPointSize + 6
        case 3: return bodyPointSize + 3
        default: return bodyPointSize + 1
        }
    }
}
