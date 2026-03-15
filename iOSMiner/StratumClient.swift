//
//  StratumClient.swift
//  iOSMiner
//
//  Created by Cooper Wang on 4/3/2026.
//

import Foundation
import Network

// MARK: - Stratum JSON-RPC Types

struct StratumRequest: Encodable {
    let id: Int
    let method: String
    let params: [StratumParam]
}

enum StratumParam: Encodable {
    case string(String)
    case int(Int)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let v): try container.encode(v)
        case .int(let v):    try container.encode(v)
        case .bool(let v):   try container.encode(v)
        }
    }
}

struct StratumResponse {
    let id: Int?
    let result: Any?
    let error: Any?
    let method: String?
    let params: [Any]?
}

// MARK: - Stratum Job

struct StratumJob {
    let jobId: String
    let prevHash: String
    let coinbase1: String
    let coinbase2: String
    let merkleBranch: [String]
    let version: String
    let nbits: String
    let ntime: String
    let cleanJobs: Bool
}

// MARK: - Connection State

nonisolated enum StratumConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case subscribed
    case authorized
    case error(String)

    var displayText: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting:   return "Connecting..."
        case .connected:    return "Connected"
        case .subscribed:   return "Subscribed"
        case .authorized:   return "Authorized"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        switch self {
        case .connected, .subscribed, .authorized: return true
        default: return false
        }
    }
}

// MARK: - StratumClient

@Observable
final class StratumClient: @unchecked Sendable {

    // Connection state (observable)
    private(set) var connectionState: StratumConnectionState = .disconnected
    private(set) var difficulty: Double = 1.0
    private(set) var currentJob: StratumJob?
    private(set) var extranonce1: String = ""
    private(set) var extranonce2Size: Int = 4
    private(set) var acceptedShares: Int = 0
    private(set) var rejectedShares: Int = 0
    private(set) var lastLog: String = ""

    /// Full log buffer (last N entries)
    private(set) var logEntries: [String] = []
    private let maxLogEntries = 200

    /// Called on main thread when a new job arrives (or difficulty changes).
    var onNewJob: ((StratumJob) -> Void)?

    /// Called on main thread when the connection drops unexpectedly (error or server close).
    var onDisconnect: (() -> Void)?

    // Configuration
    var poolHost: String = ""
    var poolPort: UInt16 = 3333
    var walletAddress: String = ""
    var workerName: String = ""
    var workerPassword: String = "x"

    /// The identity sent to the pool: "wallet.worker" or just "wallet"
    var fullWorkerIdentity: String {
        if workerName.isEmpty {
            return walletAddress
        }
        return "\(walletAddress).\(workerName)"
    }

    // Private
    private var connection: NWConnection?
    private var requestId: Int = 0
    private var receiveBuffer = Data()

    // MARK: - Connect / Disconnect

    func connect() {
        guard connectionState == .disconnected || isErrorState else { return }

        connectionState = .connecting
        log("Connecting to \(poolHost):\(poolPort)...")

        let host = NWEndpoint.Host(poolHost)
        let port = NWEndpoint.Port(integerLiteral: poolPort)

        // Enable TCP keepalive to prevent NAT/router idle timeout
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30       // send first keepalive after 30s idle
        tcpOptions.keepaliveInterval = 15   // then every 15s
        tcpOptions.keepaliveCount = 4       // drop after 4 missed probes
        tcpOptions.connectionTimeout = 15   // 15s connect timeout

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        connection = NWConnection(host: host, port: port, using: params)

        connection?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                self?.handleConnectionState(state)
            }
        }

        connection?.start(queue: .global(qos: .userInitiated))
    }

    func disconnect() {
        log("Disconnecting...")
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        requestId = 0
        currentJob = nil
        connectionState = .disconnected
    }

    /// Reset share counters — call only on fresh session start, not on reconnect.
    func resetShareCounts() {
        acceptedShares = 0
        rejectedShares = 0
    }

    // MARK: - Connection State Handler

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionState = .connected
            log("TCP connected")
            startReceiving()
            sendSubscribe()

        case .failed(let error):
            connectionState = .error(error.localizedDescription)
            log("Connection failed: \(error.localizedDescription)")
            NotificationManager.shared.notifyError("Connection failed: \(error.localizedDescription)")
            connection?.cancel()
            connection = nil
            onDisconnect?()

        case .cancelled:
            connectionState = .disconnected

        case .waiting(let error):
            log("Waiting: \(error.localizedDescription)")

        default:
            break
        }
    }

    // MARK: - Receive Loop

    private func startReceiving() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self else { return }

            if let data = content {
                DispatchQueue.main.async {
                    self.receiveBuffer.append(data)
                    self.processBuffer()
                }
            }

            if let error {
                DispatchQueue.main.async {
                    self.connectionState = .error(error.localizedDescription)
                    self.log("Receive error: \(error.localizedDescription)")
                    self.onDisconnect?()
                }
                return
            }

            if isComplete {
                DispatchQueue.main.async {
                    self.connectionState = .disconnected
                    self.log("Server closed connection")
                    NotificationManager.shared.notifyDisconnected(reason: "Server closed the connection")
                    self.onDisconnect?()
                }
                return
            }

            // Continue receiving
            self.startReceiving()
        }
    }

    private func processBuffer() {
        // Split on newlines — each line is a JSON message
        while let newlineRange = receiveBuffer.range(of: Data("\n".utf8)) {
            let lineData = receiveBuffer.subdata(in: receiveBuffer.startIndex..<newlineRange.lowerBound)
            receiveBuffer.removeSubrange(receiveBuffer.startIndex...newlineRange.lowerBound)

            guard let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            handleMessage(json)
        }
    }

    // MARK: - Message Handling

    private func handleMessage(_ json: [String: Any]) {
        // Server notification (has "method", id is null)
        if let method = json["method"] as? String {
            let params = json["params"] as? [Any] ?? []
            handleNotification(method: method, params: params)
            return
        }

        // Response to our request (has "id")
        if let id = json["id"] as? Int {
            let result = json["result"]
            let error = json["error"]
            handleResponse(id: id, result: result, error: error)
        }
    }

    private func handleNotification(method: String, params: [Any]) {
        switch method {
        case "mining.notify":
            handleMiningNotify(params)

        case "mining.set_difficulty":
            if let diff = parseDifficulty(params.first) {
                difficulty = diff
                log("Difficulty set to \(diff) (target: \(DifficultyUtil.targetHex(for: diff).prefix(16))...)")
            } else {
                log("Failed to parse difficulty from: \(params)")
            }
            // Re-trigger mining with updated difficulty if we have a current job
            if let job = currentJob {
                onNewJob?(job)
            }

        default:
            log("Unknown notification: \(method)")
        }
    }

    /// Parse difficulty from various JSON number types pools may send.
    private func parseDifficulty(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return nil
    }

    private func handleResponse(id: Int, result: Any?, error: Any?) {
        // id 1 = subscribe response
        if id == 1 {
            if let resultArray = result as? [Any], resultArray.count >= 3 {
                extranonce1 = resultArray[1] as? String ?? ""
                extranonce2Size = resultArray[2] as? Int ?? 4
                connectionState = .subscribed
                log("Subscribed -- extranonce1: \(extranonce1), en2 size: \(extranonce2Size)")
                sendAuthorize()
            } else {
                let errMsg = parseError(error)
                connectionState = .error("Subscribe failed: \(errMsg)")
                log("Subscribe failed: \(errMsg)")
            }
        }

        // id 2 = authorize response
        if id == 2 {
            if let authorized = result as? Bool, authorized {
                connectionState = .authorized
                log("Worker authorized as \(fullWorkerIdentity)")
            } else {
                let errMsg = parseError(error)
                connectionState = .error("Auth failed: \(errMsg)")
                log("Authorization failed: \(errMsg)")
            }
        }

        // id >= 10 = submit response
        if id >= 10 {
            // Log raw response for debugging
            let resultDesc = result.map { "\($0)" } ?? "nil"
            let errorDesc = error.map { "\($0)" } ?? "nil"

            if let accepted = result as? Bool, accepted {
                acceptedShares += 1
                log("Share ACCEPTED (#\(acceptedShares))")
                NotificationManager.shared.notifyShareAccepted(total: acceptedShares)
            } else if result is NSNull || result == nil || (result as? Bool) == false {
                rejectedShares += 1
                let errMsg = parseError(error)
                log("Share REJECTED: \(errMsg) [raw error=\(errorDesc), result=\(resultDesc)]")
                NotificationManager.shared.notifyShareRejected(total: rejectedShares, reason: errMsg)
            } else {
                // Unexpected response format
                rejectedShares += 1
                log("Share response unknown: result=\(resultDesc) error=\(errorDesc)")
            }
        }
    }

    private func handleMiningNotify(_ params: [Any]) {
        guard params.count >= 9,
              let jobId = params[0] as? String,
              let prevHash = params[1] as? String,
              let coinbase1 = params[2] as? String,
              let coinbase2 = params[3] as? String,
              let merkleBranch = params[4] as? [String],
              let version = params[5] as? String,
              let nbits = params[6] as? String,
              let ntime = params[7] as? String,
              let cleanJobs = params[8] as? Bool
        else {
            log("Invalid mining.notify params (count=\(params.count))")
            return
        }

        currentJob = StratumJob(
            jobId: jobId,
            prevHash: prevHash,
            coinbase1: coinbase1,
            coinbase2: coinbase2,
            merkleBranch: merkleBranch,
            version: version,
            nbits: nbits,
            ntime: ntime,
            cleanJobs: cleanJobs
        )

        log("Job: \(jobId) clean=\(cleanJobs) diff=\(difficulty) branches=\(merkleBranch.count)")
        onNewJob?(currentJob!)
    }

    // MARK: - Send Messages

    private func sendSubscribe() {
        let req = StratumRequest(
            id: 1,
            method: "mining.subscribe",
            params: [.string("iOSMiner/1.0")]
        )
        send(req)
    }

    private func sendAuthorize() {
        let req = StratumRequest(
            id: 2,
            method: "mining.authorize",
            params: [.string(fullWorkerIdentity), .string(workerPassword)]
        )
        send(req)
        log("Authorizing as \(fullWorkerIdentity)")
    }

    func submitShare(jobId: String, extranonce2: String, ntime: String, nonce: String) {
        requestId = max(requestId, 10) + 1
        let req = StratumRequest(
            id: requestId,
            method: "mining.submit",
            params: [
                .string(fullWorkerIdentity),
                .string(jobId),
                .string(extranonce2),
                .string(ntime),
                .string(nonce)
            ]
        )
        send(req)
        log("Submitting share: job=\(jobId) en2=\(extranonce2) nonce=\(nonce)")
    }

    private func send(_ request: StratumRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        var payload = data
        payload.append(contentsOf: "\n".utf8)

        connection?.send(content: payload, completion: .contentProcessed { [weak self] error in
            if let error {
                DispatchQueue.main.async {
                    self?.log("Send error: \(error.localizedDescription)")
                }
            }
        })
    }

    // MARK: - Helpers

    func clearLogs() {
        logEntries.removeAll()
    }

    private var isErrorState: Bool {
        if case .error = connectionState { return true }
        return false
    }

    private func parseError(_ error: Any?) -> String {
        if let errArray = error as? [Any] {
            // Common format: [code, "message", traceback]
            if errArray.count >= 2, let msg = errArray[1] as? String {
                let code = errArray[0] as? Int
                return code != nil ? "[\(code!)] \(msg)" : msg
            }
            return "Error array: \(errArray)"
        }
        if let errDict = error as? [String: Any] {
            return "Error dict: \(errDict)"
        }
        if let errStr = error as? String {
            return errStr
        }
        if error is NSNull {
            return "null (no error details)"
        }
        if error == nil {
            return "nil (result was not true)"
        }
        return "Unknown format: \(String(describing: error))"
    }

    func log(_ message: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let entry = "[\(ts)] \(message)"
        lastLog = entry
        logEntries.append(entry)
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst()
        }
        print("[Stratum] \(message)")
    }
}
