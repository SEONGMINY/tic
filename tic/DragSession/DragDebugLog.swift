import Foundation
import OSLog

enum DragDebugLog {
    private static let logger = Logger(
        subsystem: "com.miny.tic",
        category: "drag-debug"
    )

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TIC_DRAG_DEBUG"] == "1"
            || ProcessInfo.processInfo.arguments.contains("-TIC_DRAG_DEBUG")
    }

    static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        let value = message()
        logger.debug("\(value, privacy: .public)")
    }
}
