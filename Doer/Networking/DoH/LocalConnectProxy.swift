import Foundation
import Network

final class LocalConnectProxy {
    private let queue = DispatchQueue(label: "dexo.doh.connect-proxy")
    private let resolver: DohResolver
    private let requestedPort: UInt16
    private var listener: NWListener?
    private var boundPort: UInt16?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var hostAttemptOffsets: [String: Int] = [:]

    init(resolver: DohResolver, port: UInt16 = 0) {
        self.resolver = resolver
        self.requestedPort = port
    }

    var proxyPort: UInt16? {
        boundPort
    }

    var isRunning: Bool {
        listener != nil && boundPort != nil
    }

    func start() throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: requestedPort) else {
            throw LocalConnectProxyError.invalidPort
        }

        let parameters = NWParameters.tcp
        if let loopback = IPv4Address("127.0.0.1") {
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(loopback), port: endpointPort)
        }
        let listener = try NWListener(using: parameters, on: endpointPort)
        let readySemaphore = DispatchSemaphore(value: 0)
        let stateLock = NSLock()
        var startError: Error?

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleClient(connection)
        }
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                stateLock.lock()
                self?.boundPort = listener?.port?.rawValue
                if self?.boundPort == nil {
                    startError = LocalConnectProxyError.invalidPort
                }
                if let port = self?.boundPort {
                    DohDebugLog.record("Local CONNECT proxy ready on 127.0.0.1:\(port)")
                }
                stateLock.unlock()
                readySemaphore.signal()
            case .failed(let error):
                stateLock.lock()
                startError = LocalConnectProxyError.listenerFailed(error)
                stateLock.unlock()
                self?.stop()
                readySemaphore.signal()
            case .cancelled:
                stateLock.lock()
                if self?.boundPort == nil, startError == nil {
                    startError = LocalConnectProxyError.startTimedOut
                    readySemaphore.signal()
                }
                stateLock.unlock()
            default:
                break
            }
        }
        self.listener = listener
        listener.start(queue: queue)

        guard readySemaphore.wait(timeout: .now() + 2) == .success else {
            stop()
            throw LocalConnectProxyError.startTimedOut
        }

        stateLock.lock()
        let error = startError
        let hasPort = boundPort != nil
        stateLock.unlock()

        if let error {
            throw error
        }
        guard hasPort else {
            stop()
            throw LocalConnectProxyError.invalidPort
        }
    }

    func stop() {
        let active = connections.values
        connections.removeAll()
        active.forEach { $0.cancel() }
        listener?.cancel()
        listener = nil
        boundPort = nil
    }

    private func handleClient(_ client: NWConnection) {
        let id = ObjectIdentifier(client)
        connections[id] = client
        var didStartReading = false
        client.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready:
                guard !didStartReading else { return }
                didStartReading = true
                self.readHeader(from: client, buffer: Data())
            case .failed(let error):
                DohDebugLog.record("Client connection failed: \(error)")
                self.close(client)
            case .cancelled:
                self.connections.removeValue(forKey: ObjectIdentifier(client))
            default:
                break
            }
        }
        client.start(queue: queue)
    }

    private func readHeader(from client: NWConnection, buffer: Data) {
        client.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil || isComplete {
                self.close(client)
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            guard nextBuffer.count <= 16_384 else {
                self.reject(client, reason: "CONNECT header too large")
                return
            }

            let headerSeparator = Data([13, 10, 13, 10])
            guard let headerRange = nextBuffer.range(of: headerSeparator) else {
                self.readHeader(from: client, buffer: nextBuffer)
                return
            }

            let headerData = nextBuffer.subdata(in: nextBuffer.startIndex ..< headerRange.upperBound)
            let remainder = nextBuffer.subdata(in: headerRange.upperBound ..< nextBuffer.endIndex)
            do {
                let request = try DohConnectRequest.parse(headerData)
                guard request.port == 443, DohResolver.isAllowedHost(request.host) else {
                    self.reject(client, reason: "unsupported target \(request.host):\(request.port)")
                    return
                }
                DohDebugLog.record("CONNECT \(request.host):\(request.port)")
                self.openTunnel(for: request, client: client, bufferedClientData: remainder)
            } catch {
                DohDebugLog.record("CONNECT parse failed: \(error), first bytes: \(Self.hexPrefix(nextBuffer))")
                self.reject(client, reason: "invalid CONNECT request")
            }
        }
    }

    private func openTunnel(for request: DohConnectRequest, client: NWConnection, bufferedClientData: Data) {
        resolver.resolve(host: request.host) { [weak self, weak client] result in
            guard let self, let client else { return }
            self.queue.async {
                switch result {
                case .failure(let error):
                    DohDebugLog.record("Resolve failed for \(request.host): \(error.localizedDescription)")
                    self.reject(client, reason: "resolve failed")
                case .success(let answer):
                    let resolvedAddresses = answer.addresses.sorted { lhs, rhs in
                        !lhs.contains(":") && rhs.contains(":")
                    }
                    let addresses = self.rotatedAddresses(for: request.host, addresses: resolvedAddresses)
                    DohDebugLog.record("Resolved \(request.host) -> \(addresses.joined(separator: ", "))")
                    guard !addresses.isEmpty,
                          let upstreamPort = NWEndpoint.Port(rawValue: request.port)
                    else {
                        self.reject(client, reason: "empty resolved address")
                        return
                    }
                    self.connectUpstream(
                        addresses: addresses,
                        port: upstreamPort,
                        addressIndex: 0,
                        client: client,
                        bufferedClientData: bufferedClientData
                    )
                }
            }
        }
    }

    private func connectUpstream(
        addresses: [String],
        port: NWEndpoint.Port,
        addressIndex: Int,
        client: NWConnection,
        bufferedClientData: Data
    ) {
        guard addressIndex < addresses.count else {
            reject(client, reason: "all upstream addresses failed")
            return
        }

        let host = Self.endpointHost(from: addresses[addressIndex])
        let upstream = NWConnection(host: host, port: port, using: .tcp)
        let upstreamId = ObjectIdentifier(upstream)
        var tunnelEstablished = false
        connections[upstreamId] = upstream
        upstream.stateUpdateHandler = { [weak self, weak upstream, weak client] state in
            guard let self, let upstream else { return }
            switch state {
            case .ready:
                tunnelEstablished = true
                DohDebugLog.record("Upstream connected \(addresses[addressIndex]):\(port.rawValue)")
                self.sendConnectSuccess(to: client, upstream: upstream, bufferedClientData: bufferedClientData)
            case .failed, .cancelled:
                self.connections.removeValue(forKey: ObjectIdentifier(upstream))
                if tunnelEstablished {
                    self.close(client)
                } else if case .failed = state, let client {
                    DohDebugLog.record("Upstream failed \(addresses[addressIndex]):\(port.rawValue), trying next")
                    self.connectUpstream(
                        addresses: addresses,
                        port: port,
                        addressIndex: addressIndex + 1,
                        client: client,
                        bufferedClientData: bufferedClientData
                    )
                }
            default:
                break
            }
        }
        upstream.start(queue: queue)
    }

    private func sendConnectSuccess(to client: NWConnection?, upstream: NWConnection, bufferedClientData: Data) {
        guard let client else {
            close(upstream)
            return
        }

        let response = Data("HTTP/1.1 200 Connection Established\r\nProxy-Agent: Dexo-DoH\r\n\r\n".utf8)
        client.send(content: response, completion: .contentProcessed { [weak self, weak client, weak upstream] error in
            guard let self, let client, let upstream else { return }
            if error != nil {
                DohDebugLog.record("CONNECT success response send failed: \(String(describing: error))")
                self.close(client)
                self.close(upstream)
                return
            }
            DohDebugLog.record("CONNECT tunnel established")
            let diagnostics = TunnelDiagnostics()
            if !bufferedClientData.isEmpty {
                diagnostics.logClientHelloIfNeeded(bufferedClientData)
                upstream.send(content: bufferedClientData, completion: .contentProcessed { [weak self, weak client, weak upstream] sendError in
                    guard let self, let client, let upstream else { return }
                    if sendError != nil {
                        DohDebugLog.record("Buffered client data send failed: \(String(describing: sendError))")
                        self.close(client)
                        self.close(upstream)
                        return
                    }
                    self.pipe(from: client, to: upstream, diagnostics: diagnostics)
                    self.pipe(from: upstream, to: client)
                })
                return
            }
            self.pipe(from: client, to: upstream, diagnostics: diagnostics)
            self.pipe(from: upstream, to: client)
        })
    }

    private func pipe(from source: NWConnection, to target: NWConnection, diagnostics: TunnelDiagnostics? = nil) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self, weak source, weak target] data, _, isComplete, error in
            guard let self, let source, let target else { return }
            if let data, !data.isEmpty {
                diagnostics?.logClientHelloIfNeeded(data)
                target.send(content: data, completion: .contentProcessed { [weak self, weak source, weak target] sendError in
                    guard let self, let source, let target else { return }
                    if sendError != nil {
                        DohDebugLog.record("Tunnel send failed: \(String(describing: sendError))")
                        self.close(source)
                        self.close(target)
                        return
                    }
                    self.pipe(from: source, to: target, diagnostics: diagnostics)
                })
                return
            }

            if isComplete || error != nil {
                if let error {
                    DohDebugLog.record("Tunnel receive failed: \(error)")
                } else {
                    DohDebugLog.record("Tunnel side closed")
                }
                close(source)
                close(target)
                return
            }
            pipe(from: source, to: target)
        }
    }

    private func reject(_ connection: NWConnection, reason: String) {
        DohDebugLog.record("Reject CONNECT: \(reason)")
        let response = Data("HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: response, completion: .contentProcessed { [weak self, weak connection] _ in
            if let connection {
                self?.close(connection)
            }
        })
    }

    private static func hexPrefix(_ data: Data, limit: Int = 16) -> String {
        data.prefix(limit)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }

    private static func endpointHost(from address: String) -> NWEndpoint.Host {
        if let ipv4 = IPv4Address(address) {
            return .ipv4(ipv4)
        }
        if let ipv6 = IPv6Address(address) {
            return .ipv6(ipv6)
        }
        return .name(address, nil)
    }

    private func rotatedAddresses(for host: String, addresses: [String]) -> [String] {
        guard !addresses.isEmpty else { return [] }
        let offset = hostAttemptOffsets[host, default: 0]
        hostAttemptOffsets[host] = offset + 1
        let start = offset % addresses.count
        return Array(addresses[start...]) + Array(addresses[..<start])
    }

    private func close(_ connection: NWConnection?) {
        guard let connection else { return }
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }
}

private final class TunnelDiagnostics {
    private var didLogClientHello = false

    func logClientHelloIfNeeded(_ data: Data) {
        guard !didLogClientHello else { return }
        didLogClientHello = true

        let isTLSHandshake = data.first == 0x16
        let hasLinuxDoSNI = data.range(of: Data("linux.do".utf8)) != nil
        DohDebugLog.record(
            "Client TLS first bytes: \(hexPrefix(data)); tlsHandshake=\(isTLSHandshake); sni_linux_do=\(hasLinuxDoSNI)"
        )
    }

    private func hexPrefix(_ data: Data, limit: Int = 16) -> String {
        data.prefix(limit)
            .map { String(format: "%02x", $0) }
            .joined(separator: " ")
    }
}

enum LocalConnectProxyError: Error {
    case invalidPort
    case listenerFailed(Error)
    case startTimedOut
}
