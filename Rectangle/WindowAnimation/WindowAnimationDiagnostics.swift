import Cocoa
import QuartzCore

/// Opt-in local timing evidence. Normal app launches do no tracing or filesystem work.
/// Example Terminal command to launch Rectangle with this enabled:
/// open -a Rectangle --env RECTANGLE_ANIMATION_TRACE_PATH="/tmp/trace.json"
enum WindowAnimationDiagnostics {
    private static let path = ProcessInfo.processInfo.environment["RECTANGLE_ANIMATION_TRACE_PATH"]
    static var enabled: Bool { !(path ?? "").isEmpty }
    private static let queue = DispatchQueue(label: "Rectangle.WindowAnimation.diagnostics", qos: .utility)
    static func event(_ name: String, fields: [String: Any] = [:]) {
        guard let path, !path.isEmpty else { return }
        var record = fields
        record["event"] = name
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        record["timestamp"] = Date().timeIntervalSince1970
        record["pid"] = getpid()
        guard JSONSerialization.isValidJSONObject(record),
              var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        queue.async {
            let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, S_IRUSR | S_IWUSR)
            guard descriptor >= 0 else { return }
            defer { close(descriptor) }
            data.withUnsafeBytes { buffer in
                guard let base = buffer.baseAddress else { return }
                _ = Darwin.write(descriptor, base, buffer.count)
            }
        }
    }
}
