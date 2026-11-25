import Foundation
import LibXray

enum LibXrayInvoker {
    enum Failure: Error {
        case cgoFailed
    }

    /// Measurements run side by side: libXray keeps them apart from its
    /// managed core, the simulator's included. Any other call waits for them
    /// and runs by itself, since it may change process-global Xray state.
    private static let access = ReadWriteLock()

    /// A cgo call blocks its thread for the length of a measurement. GCD adds
    /// threads for that; the cooperative pool is only as wide as the cores.
    private static let queue = DispatchQueue(label: "com.launchvpn.libxray", attributes: .concurrent)

    static func invoke(_ requestJson: String) async throws -> String {
        let shared = isMeasurement(requestJson)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result {
                    try access.run(shared: shared) { try perform(requestJson) }
                })
            }
        }
    }

    private static func isMeasurement(_ requestJson: String) -> Bool {
        guard requestJson.contains("\"pingBatch\""),
              let object = try? JSONSerialization.jsonObject(with: Data(requestJson.utf8)) as? [String: Any]
        else { return false }
        return object["method"] as? String == "pingBatch"
    }

    private static func perform(_ requestJson: String) throws -> String {
        let response = requestJson.withCString { pointer in
            CGoInvoke(UnsafeMutablePointer(mutating: pointer))
        }
        guard let response else { throw Failure.cgoFailed }
        defer { CGoFree(response) }
        return String(cString: response)
    }
}

/// Shared holders run together; an exclusive one runs alone. It lives as long
/// as the process.
private final class ReadWriteLock: @unchecked Sendable {
    private let lock: UnsafeMutablePointer<pthread_rwlock_t> = {
        let lock = UnsafeMutablePointer<pthread_rwlock_t>.allocate(capacity: 1)
        pthread_rwlock_init(lock, nil)
        return lock
    }()

    func run<T>(shared: Bool, _ body: () throws -> T) rethrows -> T {
        _ = shared ? pthread_rwlock_rdlock(lock) : pthread_rwlock_wrlock(lock)
        defer { pthread_rwlock_unlock(lock) }
        return try body()
    }
}

extension URL {
    func adaptedAppendPath(path: String) -> URL {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return self.appending(path: path)
        } else {
            return self.appendingPathComponent(path)
        }
    }

    func adaptedPath() -> String {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return self.path(percentEncoded: false)
        } else {
            let path = self.path
            if let cleanPath = path.removingPercentEncoding {
                return cleanPath
            }
            return path
        }
    }
}
