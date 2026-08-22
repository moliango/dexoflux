import Foundation
import Network
import Security

/// FluxDo-style CONNECT MITM: terminate client TLS with the local CA, then
/// pipe plaintext to an already-established native TLS upstream.
nonisolated final class MitmTLSBridge: @unchecked Sendable {
    private let client: NWConnection
    private let upstream: NWConnection
    private let sslQueue = DispatchQueue(label: "doer.doh.mitm-ssl")
    private var inbound = Data()
    private let lock = NSLock()
    private var ssl: SSLContext?
    private var handshakeDone = false

    init(client: NWConnection, upstream: NWConnection) {
        self.client = client
        self.upstream = upstream
    }

    func preload(_ data: Data) {
        lock.lock()
        inbound.append(data)
        lock.unlock()
    }

    func start(identity: SecIdentity, completion: @escaping (Bool) -> Void) {
        sslQueue.async { [weak self] in
            guard let self else {
                completion(false)
                return
            }
            completion(self.handshake(identity: identity))
        }
    }

    private func handshake(identity: SecIdentity) -> Bool {
        guard let context = SSLCreateContext(kCFAllocatorDefault, .serverSide, .streamType) else {
            DohDebugLog.record("MITM SSLCreateContext failed")
            return false
        }
        ssl = context
        SSLSetIOFuncs(context, { connection, data, length in
            Unmanaged<MitmTLSBridge>.fromOpaque(connection).takeUnretainedValue()
                .sslRead(data, length)
        }, { connection, data, length in
            Unmanaged<MitmTLSBridge>.fromOpaque(connection).takeUnretainedValue()
                .sslWrite(data, length)
        })
        SSLSetConnection(context, Unmanaged.passUnretained(self).toOpaque())
        SSLSetCertificate(context, [identity] as CFArray)

        var status = SSLHandshake(context)
        var spins = 0
        while status == errSSLWouldBlock, spins < 40 {
            spins += 1
            status = SSLHandshake(context)
        }
        guard status == errSecSuccess else {
            DohDebugLog.record("MITM client handshake failed: \(status)")
            return false
        }
        handshakeDone = true
        DohDebugLog.record("MITM client handshake complete")
        pipe()
        return true
    }

    private func pipe() {
        pumpClientToUpstream()
        pumpUpstreamToClient()
    }

    private func pumpClientToUpstream() {
        var buffer = [UInt8](repeating: 0, count: 16_384)
        var processed = 0
        let status = SSLRead(ssl!, &buffer, buffer.count, &processed)
        if processed > 0 {
            upstream.send(
                content: Data(buffer.prefix(processed)),
                contentContext: NWConnection.ContentContext(identifier: "doer.doh.mitm", isFinal: false),
                isComplete: false,
                completion: .contentProcessed { [weak self] error in
                    if error == nil {
                        self?.sslQueue.async { self?.pumpClientToUpstream() }
                    }
                }
            )
            return
        }
        if status == errSSLWouldBlock {
            sslQueue.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.pumpClientToUpstream()
            }
        }
    }

    private func pumpUpstreamToClient() {
        upstream.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.sslQueue.async {
                    _ = data.withUnsafeBytes { raw in
                        var processed = 0
                        return SSLWrite(self.ssl!, raw.baseAddress, data.count, &processed)
                    }
                    self.pumpUpstreamToClient()
                }
                return
            }
            if error != nil || isComplete { return }
            self.pumpUpstreamToClient()
        }
    }

    private func sslRead(_ data: UnsafeMutableRawPointer, _ length: UnsafeMutablePointer<Int>) -> OSStatus {
        let wanted = length.pointee
        lock.lock()
        if inbound.isEmpty {
            lock.unlock()
            let semaphore = DispatchSemaphore(value: 0)
            var received = Data()
            client.receive(minimumIncompleteLength: 1, maximumLength: max(wanted, 4096)) { data, _, _, _ in
                if let data { received = data }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 2)
            lock.lock()
            inbound.append(received)
        }
        let take = min(wanted, inbound.count)
        if take == 0 {
            lock.unlock()
            length.pointee = 0
            return errSSLWouldBlock
        }
        inbound.copyBytes(to: data.assumingMemoryBound(to: UInt8.self), count: take)
        inbound.removeFirst(take)
        lock.unlock()
        length.pointee = take
        return errSecSuccess
    }

    private func sslWrite(_ data: UnsafeRawPointer, _ length: UnsafeMutablePointer<Int>) -> OSStatus {
        let count = length.pointee
        let payload = Data(bytes: data, count: count)
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: NWError?
        client.send(
            content: payload,
            contentContext: NWConnection.ContentContext(identifier: "doer.doh.mitm-out", isFinal: false),
            isComplete: false,
            completion: .contentProcessed { error in
                sendError = error
                semaphore.signal()
            }
        )
        _ = semaphore.wait(timeout: .now() + 2)
        if sendError != nil {
            return errSSLClosedAbort
        }
        return errSecSuccess
    }
}
