import Foundation

@MainActor
final class TesterApi: @preconcurrency TesterHostApi {
    /// TestFlight installs carry a sandbox receipt, and App Store installs of the
    /// same binary a production one. Builds run from Xcode have none.
    func isTestFlight(completion: @escaping (Result<Bool, Error>) -> Void) {
        completion(.success(Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"))
    }

    func readTunnelMemory(completion: @escaping (Result<TunnelMemory?, Error>) -> Void) {
        Task {
            let reading = await VPNManager.shared.readTunnelMemory()
            completion(.success(reading.map {
                TunnelMemory(footprint: Int64($0.footprint), peak: Int64($0.peak), limit: Int64($0.limit))
            }))
        }
    }
}
