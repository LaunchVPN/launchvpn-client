import Foundation
import Network
import NetworkExtension
import Security
import dnssd
#if os(iOS)
import Flutter
#elseif os(macOS)
import AppKit
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif

@MainActor
final class AppHostApi: @preconcurrency BridgeHostApi {
    // Retain the native status observer for the bridge's lifetime.
    private let flutterApi: AppFlutterApi
    init(flutterApi: AppFlutterApi) {
        self.flutterApi = flutterApi
    }
    
    func getTunFilesDir(completion: @escaping (Result<String, any Error>) -> Void) {
        if let groupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId()) {
            let path = groupUrl.adaptedPath()
            completion(.success(path))
        } else {
            completion(.success(""))
        }
    }

    func readVpnStatus(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            let permission = await VPNManager.shared.queryPlatformPermission()
            do {
                let status = try await VPNManager.shared.readVpnStatus()
                if permission.state == .failed {
                    completion(.success(NativeVpnCommandResult(
                        state: .failed,
                        permission: permission,
                        message: permission.message
                    )))
                } else {
                    completion(.success(NativeVpnCommandResult(
                        state: .success,
                        status: status,
                        permission: permission,
                        message: status == .disconnected ? VPNManager.shared.lastCommandError : nil
                    )))
                }
            } catch {
                completion(.success(NativeVpnCommandResult(
                    state: .failed,
                    permission: permission,
                    message: error.localizedDescription
                )))
            }
        }
    }
    
    func startVpn(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.startVpn()))
        }
    }

    func stopVpn(completion: @escaping (Result<NativeVpnCommandResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.stopVpn()))
        }
    }

    func invoke(requestJson: String, completion: @escaping (Result<String, any Error>) -> Void) {
        Task {
            do {
                let request = try await PingOutsideTunnel.prepare(requestJson)
                completion(.success(try await LibXrayInvoker.invoke(request)))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func getDeviceIdentity(completion: @escaping (Result<DeviceIdentity, any Error>) -> Void) {
        completion(Result {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            #if os(iOS)
            let os = "iOS"
            #else
            let os = "macOS"
            #endif
            return DeviceIdentity(
                hwid: try NativeDevice.readOrCreateHwid(),
                os: os,
                osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                model: NativeDevice.machineModel()
            )
        })
    }

    func queryPlatformPermission(completion: @escaping (Result<PlatformPermissionResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.queryPlatformPermission()))
        }
    }

    func requestPlatformPermission(completion: @escaping (Result<PlatformPermissionResult, any Error>) -> Void) {
        Task {
            completion(.success(await VPNManager.shared.requestPlatformPermission()))
        }
    }
    
    /// android
    func getInstalledApps(completion: @escaping (Result<[AndroidAppInfo], any Error>) -> Void) {
        completion(.success([]))
    }

    func getAppIcon(packageName: String, completion: @escaping (Result<FlutterStandardTypedData?, any Error>) -> Void) {
        completion(.success(nil))
    }

    /// macOS
    func useSystemExtension(completion: @escaping (Result<Bool, any Error>) -> Void) {
        completion(.success(Constants.useSystemExtension))
    }

    func appleVpnCapabilities(completion: @escaping (Result<AppleVpnCapabilities, any Error>) -> Void) {
        let serviceExclusions: Bool
        let deviceCommunication: Bool
        if #available(iOS 16.4, macOS 13.3, *) {
            serviceExclusions = true
        } else {
            serviceExclusions = false
        }
        if #available(iOS 17.4, macOS 14.4, *) {
            deviceCommunication = true
        } else {
            deviceCommunication = false
        }
        completion(.success(AppleVpnCapabilities(
            serviceExclusions: serviceExclusions,
            deviceCommunication: deviceCommunication
        )))
    }

    func queryLaunchAtLogin(
        completion: @escaping (Result<NativeLaunchAtLoginResult, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.query()))
#else
        completion(.success(NativeLaunchAtLoginResult(
            state: .unavailable,
            message: nil
        )))
#endif
    }

    func setLaunchAtLogin(
        enabled: Bool,
        completion: @escaping (Result<NativeLaunchAtLoginResult, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.setEnabled(enabled)))
#else
        completion(.success(NativeLaunchAtLoginResult(
            state: .unavailable,
            message: nil
        )))
#endif
    }

    func openLaunchAtLoginSettings(
        completion: @escaping (Result<Bool, any Error>) -> Void
    ) {
#if os(macOS)
        completion(.success(LaunchAtLoginService.openSettings()))
#else
        completion(.success(false))
#endif
    }

    /// Apple app icon
    func setAppIcon(appIcon: String, completion: @escaping (Result<Bool, any Error>) -> Void) {
#if os(iOS)
        var iconName: String? = appIcon
        if appIcon.isEmpty {
            iconName = nil
        }
        if UIApplication.shared.alternateIconName == iconName {
            completion(.success(true))
            return
        }
        UIApplication.shared.setAlternateIconName(iconName) { error in
            if let error = error {
                YGLog(error.localizedDescription)
                completion(.failure(error))
            } else {
                completion(.success(true))
            }
        }
#elseif os(macOS)
        completion(.success(DockIconService.setIcon(appIcon)))
#endif
    }

    func getCurrentAppIcon(completion: @escaping (Result<String, any Error>) -> Void) {
#if os(iOS)
        var appIcon = ""
        if let iconName = UIApplication.shared.alternateIconName {
            appIcon = iconName
        }
        completion(.success(appIcon))
#elseif os(macOS)
        completion(.success(DockIconService.currentIconName))
#endif
    }
}

/// The HWID is a UUID kept in the Keychain, which outlives the app across
/// reinstalls. `ThisDeviceOnly` keeps it out of backups: a restored phone is a
/// new device.
private enum NativeDevice {
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "hwid",
            kSecAttrAccount as String: "device",
        ]
    }

    static func readOrCreateHwid() throws -> String {
        if let saved = try read() { return saved }
        let created = UUID().uuidString
        var item = query
        item[kSecValueData as String] = Data(created.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        if status == errSecDuplicateItem, let saved = try read() { return saved }
        guard status == errSecSuccess else { throw failure(status) }
        return created
    }

    // Only a missing item may create a new HWID. A locked Keychain must fail, or
    // the panel would count this phone as another device.
    private static func read() throws -> String? {
        var search = query
        search[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(search as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw failure(status) }
        return String(decoding: data, as: UTF8.self)
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }

    static func machineModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}

/// The App's own traffic takes the tunnel, so a measurement from here would
/// describe the tunnel. A socket bound to the physical interface goes past it,
/// unless the tunnel captures all traffic, where Locations does not measure.
/// Server names resolve past it too: through the tunnel they added seconds.
enum PingOutsideTunnel {
    enum Failure: LocalizedError {
        case noPhysicalInterface

        var errorDescription: String? {
            "No Wi-Fi or cellular interface to measure past the tunnel."
        }
    }

    /// A measurement that cannot get past a running tunnel fails rather than
    /// measure the tunnel.
    static func prepare(_ requestJson: String) async throws -> String {
        // Only measurements need the work below, and every other call skips it.
        guard requestJson.contains("\"pingBatch\""),
              object(requestJson)?["method"] as? String == "pingBatch",
              await tunnelLetsPast()
        else { return requestJson }
        guard let interface = await physicalInterface(),
              var request = object(requestJson),
              var payload = request["payload"] as? [String: Any],
              let configs = payload["configs"] as? [[String: Any]]
        else { throw Failure.noPhysicalInterface }
        let xrays = configs.map { ($0["xrayJson"] as? String).flatMap(object) }
        let names = xrays.flatMap { $0.map(outbounds) ?? [] }
            .filter { nameKeeper($0) != nil }
            .reduce(into: Set<String>()) { $0.formUnion(Self.names($1)) }
        let addresses = await resolve(names, on: interface.index)
        payload["configs"] = zip(configs, xrays).map { config, xray in
            guard var xray else { return config }
            xray["outbounds"] = outbounds(xray).map {
                dialing(bound($0, to: interface.name), via: addresses)
            }
            guard let xrayJson = text(xray) else { return config }
            var config = config
            config["xrayJson"] = xrayJson
            return config
        }
        request["payload"] = payload
        guard let prepared = text(request) else { throw Failure.noPhysicalInterface }
        return prepared
    }

    private static func outbounds(_ xray: [String: Any]) -> [[String: Any]] {
        xray["outbounds"] as? [[String: Any]] ?? []
    }

    /// The outbound dials through [interface].
    private static func bound(_ outbound: [String: Any], to interface: String) -> [String: Any] {
        var outbound = outbound
        var stream = outbound["streamSettings"] as? [String: Any] ?? [:]
        var sockopt = stream["sockopt"] as? [String: Any] ?? [:]
        sockopt["interface"] = interface
        stream["sockopt"] = sockopt
        outbound["streamSettings"] = stream
        return outbound
    }

    /// Transports that name the server by the TLS or Reality server name when
    /// they have no host of their own, as Xray builds them.
    private static let namedByServerName: Set = ["tcp", "raw", "ws", "httpupgrade", "xhttp", "splithttp"]
    private static let securitySettings = ["tls": "tlsSettings", "reality": "realitySettings"]

    /// The stream settings of an outbound that can dial an address and keep
    /// its server's name, and the key of the TLS or Reality settings that keep
    /// it. Null for one that resolves names its own way: chained through
    /// another outbound, or with a domain strategy.
    private static func nameKeeper(_ outbound: [String: Any]) -> (stream: [String: Any], key: String)? {
        guard let stream = outbound["streamSettings"] as? [String: Any],
              namedByServerName.contains(stream["network"] as? String ?? "tcp"),
              let key = (stream["security"] as? String).flatMap({ securitySettings[$0] })
        else { return nil }
        let sockopt = stream["sockopt"] as? [String: Any] ?? [:]
        guard sockopt["dialerProxy"] == nil,
              (sockopt["domainStrategy"] as? String ?? "AsIs").lowercased() == "asis"
        else { return nil }
        return (stream, key)
    }

    /// The server names an outbound dials, addresses left out.
    private static func names(_ outbound: [String: Any]) -> Set<String> {
        var names = Set<String>()
        _ = servers(outbound) { names.insert($0); return $0 }
        return names.filter {
            IPv4Address($0) == nil
                && IPv6Address($0.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) == nil
        }
    }

    /// The outbound dials the address [addresses] found for its server's name.
    /// TLS keeps the name as its server name, which Xray also sends as the
    /// host, so the server sees what it saw before. An outbound that cannot
    /// keep the name dials it as it is.
    private static func dialing(_ outbound: [String: Any], via addresses: [String: String]) -> [String: Any] {
        guard let keeper = nameKeeper(outbound) else { return outbound }
        var stream = keeper.stream
        let key = keeper.key
        var dialed = servers(outbound) { addresses[$0] ?? $0 }
        var security = stream[key] as? [String: Any] ?? [:]
        if (security["serverName"] as? String ?? "").isEmpty {
            // Only the one name the outbound has can stand in for it.
            let names = Self.names(outbound)
            guard names.count == 1 else { return outbound }
            security["serverName"] = names.first
            stream[key] = security
            dialed["streamSettings"] = stream
        }
        return dialed
    }

    /// The outbound with [change] applied to each server address, in any shape
    /// Xray takes: one address, or a list of servers.
    private static func servers(_ outbound: [String: Any], _ change: (String) -> String) -> [String: Any] {
        guard var settings = outbound["settings"] as? [String: Any] else { return outbound }
        if let address = settings["address"] as? String {
            settings["address"] = change(address)
        }
        for key in ["vnext", "servers"] {
            guard let list = settings[key] as? [[String: Any]] else { continue }
            settings[key] = list.map { server in
                var server = server
                if let address = server["address"] as? String {
                    server["address"] = change(address)
                }
                return server
            }
        }
        var outbound = outbound
        outbound["settings"] = settings
        return outbound
    }

    /// Addresses by name. A name that does not resolve is left out, so its
    /// outbound resolves it the slow way.
    private static func resolve(_ names: Set<String>, on interface: UInt32) async -> [String: String] {
        await withTaskGroup(of: (String, String?).self) { group in
            for name in names {
                group.addTask { (name, await ScopedLookup.address(of: name, on: interface)) }
            }
            var addresses: [String: String] = [:]
            for await (name, address) in group {
                addresses[name] = address
            }
            return addresses
        }
    }

    private static func object(_ json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func text(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @MainActor
    private static func tunnelLetsPast() -> Bool {
        guard let manager = VPNManager.shared.vpn,
              manager.connection.status == .connected
        else { return false }
        return manager.protocolConfiguration?.includeAllNetworks != true
    }

    /// Wi-Fi before cellular, as the system prefers it.
    private static func physicalInterface() async -> (name: String, index: UInt32)? {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor(prohibitedInterfaceTypes: [.other, .loopback])
            let answer = Once()
            monitor.pathUpdateHandler = { path in
                guard answer.take() else { return }
                // The handler holds the monitor, so it goes with it.
                monitor.pathUpdateHandler = nil
                monitor.cancel()
                let physical = path.availableInterfaces.first {
                    $0.type == .wifi || $0.type == .cellular
                }
                continuation.resume(returning: physical.map { ($0.name, UInt32($0.index)) })
            }
            monitor.start(queue: DispatchQueue(label: "com.launchvpn.ping-path"))
        }
    }

    /// The monitor may report again before it stops; only its first path counts.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var taken = false

        func take() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if taken { return false }
            taken = true
            return true
        }
    }

    /// Resolves a name through one interface's own DNS servers, the way the
    /// system resolves for that network without the tunnel. IPv4 comes first,
    /// and an IPv6 answer waits a moment for it: one address gets no fallback
    /// to the other family, as a dial by name does.
    private final class ScopedLookup: @unchecked Sendable {
        private static let timeout = DispatchTimeInterval.seconds(3)
        /// How long one family's answer waits for the other's.
        private static let otherFamily = DispatchTimeInterval.milliseconds(300)

        // The start, the answers and the timers share this queue, so the state
        // needs no lock. Each timer holds the lookup until it fires.
        private let queue = DispatchQueue(label: "com.launchvpn.ping-dns")
        private var service: DNSServiceRef?
        private var answer: CheckedContinuation<String?, Never>?
        private var ipv6: String?
        private var noIPv4 = false
        private var noIPv6 = false

        static func address(of name: String, on interface: UInt32) async -> String? {
            let lookup = ScopedLookup()
            return await withCheckedContinuation { continuation in
                lookup.queue.async { lookup.start(name, interface, continuation) }
            }
        }

        private func start(_ name: String, _ interface: UInt32, _ continuation: CheckedContinuation<String?, Never>) {
            answer = continuation
            queue.asyncAfter(deadline: .now() + Self.timeout) { self.finish(self.ipv6) }
            let status = DNSServiceGetAddrInfo(
                // Negative answers too, so a name without records ends at once.
                &service, DNSServiceFlags(kDNSServiceFlagsReturnIntermediates), interface, 0, name,
                { _, flags, _, error, _, address, _, context in
                    guard let context else { return }
                    Unmanaged<ScopedLookup>.fromOpaque(context).takeUnretainedValue()
                        .receive(error, flags, address)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            guard status == DNSServiceErrorType(kDNSServiceErr_NoError), let service,
                  DNSServiceSetDispatchQueue(service, queue) == DNSServiceErrorType(kDNSServiceErr_NoError)
            else { return finish(nil) }
        }

        private func receive(_ error: DNSServiceErrorType, _ flags: DNSServiceFlags, _ address: UnsafePointer<sockaddr>?) {
            let ipv4 = address.map { Int32($0.pointee.sa_family) == AF_INET } ?? true
            switch error {
            case DNSServiceErrorType(kDNSServiceErr_NoError):
                guard flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
                      let address, let text = Self.numeric(address)
                else { return }
                if ipv4 { return finish(text) }
                ipv6 = ipv6 ?? text
            case DNSServiceErrorType(kDNSServiceErr_NoSuchRecord):
                if ipv4 { noIPv4 = true } else { noIPv6 = true }
                if noIPv4 && noIPv6 { return finish(nil) }
            default:
                return finish(ipv6)
            }
            // The system may not ask for the other family at all.
            queue.asyncAfter(deadline: .now() + Self.otherFamily) { self.finish(self.ipv6) }
        }

        private func finish(_ address: String?) {
            guard let answer else { return }
            self.answer = nil
            if let service { DNSServiceRefDeallocate(service) }
            service = nil
            answer.resume(returning: address)
        }

        private static func numeric(_ address: UnsafePointer<sockaddr>) -> String? {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                address, socklen_t(address.pointee.sa_len),
                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST
            ) == 0 else { return nil }
            return String(cString: host)
        }
    }
}
