import Foundation

struct MobileBridgeHealthResponse: Codable, Equatable {
    let ok: Bool
    let `protocol`: Int
    let serverName: String
    let pairedDevices: Int

    enum CodingKeys: String, CodingKey {
        case ok
        case `protocol`
        case serverName = "server_name"
        case pairedDevices = "paired_devices"
    }
}

struct MobilePairRequest: Codable, Equatable {
    let code: String
    let deviceName: String

    enum CodingKeys: String, CodingKey {
        case code
        case deviceName = "device_name"
    }
}

struct MobilePairResponse: Codable, Equatable {
    let ok: Bool
    let deviceId: String
    let token: String
    let serverName: String

    enum CodingKeys: String, CodingKey {
        case ok
        case deviceId = "device_id"
        case token
        case serverName = "server_name"
    }
}

struct MobilePairingPayload: Equatable {
    let hostURL: String
    let code: String

    var uriString: String {
        var components = URLComponents()
        components.scheme = "kasugai"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: hostURL),
            URLQueryItem(name: "code", value: code),
        ]
        return components.string ?? ""
    }

    static func parse(_ raw: String) -> MobilePairingPayload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let components = URLComponents(string: trimmed),
            components.scheme?.lowercased() == "kasugai",
            components.host?.lowercased() == "pair",
            let items = components.queryItems
        else {
            return nil
        }
        let host =
            items.first(where: { $0.name == "host" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let code =
            items.first(where: { $0.name == "code" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty, !code.isEmpty else {
            return nil
        }
        return MobilePairingPayload(
            hostURL: normalizeHostURL(host), code: normalizePairingCode(code))
    }

    static func normalizeHostURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        if trimmed.isEmpty {
            return ""
        }
        if !trimmed.contains("://") {
            let lower = trimmed.lowercased()
            let isLoopback =
                lower.hasPrefix("127.0.0.1")
                || lower.hasPrefix("localhost")
                || lower.hasPrefix("[::1]")
            trimmed = (isLoopback ? "http://" : "https://") + trimmed
        }
        return trimmed
    }

    static func normalizePairingCode(_ raw: String) -> String {
        let stripped = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard stripped.count == 8 else {
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        let prefix = stripped.prefix(4)
        let suffix = stripped.suffix(4)
        return "\(prefix)-\(suffix)"
    }
}

struct PairedMobileDeviceInfo: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let createdAtMs: Int64
    let lastSeenAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAtMs = "created_at_ms"
        case lastSeenAtMs = "last_seen_at_ms"
    }
}

struct MobileBridgeStatusSnapshot: Codable, Equatable {
    let enabled: Bool
    let running: Bool
    let bindHost: String
    let localPort: UInt16
    let tailscaleAvailable: Bool
    let tailscaleRunning: Bool
    let tailscaleServeActive: Bool
    let tailscaleDnsName: String
    let tailscaleHttpsPort: UInt16
    let publicBaseURL: String
    let serverName: String
    let activePairingCode: String
    let pairingExpiresAtMs: Int64
    let pairedDevices: [PairedMobileDeviceInfo]
    let connectedStreamCount: Int
    let lastError: String

    enum CodingKeys: String, CodingKey {
        case enabled
        case running
        case bindHost = "bind_host"
        case localPort = "local_port"
        case tailscaleAvailable = "tailscale_available"
        case tailscaleRunning = "tailscale_running"
        case tailscaleServeActive = "tailscale_serve_active"
        case tailscaleDnsName = "tailscale_dns_name"
        case tailscaleHttpsPort = "tailscale_https_port"
        case publicBaseURL = "public_base_url"
        case serverName = "server_name"
        case activePairingCode = "active_pairing_code"
        case pairingExpiresAtMs = "pairing_expires_at_ms"
        case pairedDevices = "paired_devices"
        case connectedStreamCount = "connected_stream_count"
        case lastError = "last_error"
    }

    static let disabled = MobileBridgeStatusSnapshot(
        enabled: false,
        running: false,
        bindHost: "127.0.0.1",
        localPort: 17921,
        tailscaleAvailable: false,
        tailscaleRunning: false,
        tailscaleServeActive: false,
        tailscaleDnsName: "",
        tailscaleHttpsPort: 9443,
        publicBaseURL: "",
        serverName: "",
        activePairingCode: "",
        pairingExpiresAtMs: 0,
        pairedDevices: [],
        connectedStreamCount: 0,
        lastError: ""
    )
}

struct MobileActionRequest: Codable, Equatable {
    let method: String
    var projectId: Int64?
    var threadId: Int64?
    var turnId: Int64?
    var title: String?
    var provider: String?
    var model: String?
    var effort: String?
    var text: String?
    var attachments: [String]?
    var approve: Bool?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case method
        case projectId = "project_id"
        case threadId = "thread_id"
        case turnId = "turn_id"
        case title
        case provider
        case model
        case effort
        case text
        case attachments
        case approve
        case enabled
    }
}

struct MobileActionResponse: Codable, Equatable {
    let ok: Bool
    let error: String?
    let intValue: Int64?
    let boolValue: Bool?
    let stringValue: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case intValue = "int_value"
        case boolValue = "bool_value"
        case stringValue = "string_value"
    }
}

struct MobileFileEntry: Codable, Equatable, Identifiable {
    var id: String { relativePath }
    let name: String
    let relativePath: String
    let fullPath: String
    let isDirectory: Bool
    let sizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case relativePath = "relative_path"
        case fullPath = "full_path"
        case isDirectory = "is_directory"
        case sizeBytes = "size_bytes"
    }
}

struct MobileDirectoryListing: Codable, Equatable {
    let rootPath: String
    let relativePath: String
    let entries: [MobileFileEntry]

    enum CodingKeys: String, CodingKey {
        case rootPath = "root_path"
        case relativePath = "relative_path"
        case entries
    }
}

struct MobileTerminalOpenRequest: Codable, Equatable {
    let cols: UInt16
    let rows: UInt16
}

struct MobileTerminalInputRequest: Codable, Equatable {
    let text: String
}

struct MobileTerminalResizeRequest: Codable, Equatable {
    let cols: UInt16
    let rows: UInt16
}

struct MobileAttachmentUploadRequest: Codable, Equatable {
    let filename: String
    let dataBase64: String

    enum CodingKeys: String, CodingKey {
        case filename
        case dataBase64 = "data_base64"
    }
}

struct MobileAttachmentUploadResponse: Codable, Equatable {
    let ok: Bool
    let path: String
    let name: String
}

struct MobileFilePreviewPayload: Codable, Equatable {
    let path: String
    let name: String
    let kind: String
    let sizeLabel: String
    let text: String?
    let mediaUrl: String?
    let highlightLineStart: Int?
    let highlightLineEnd: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case kind
        case sizeLabel = "size_label"
        case text
        case mediaUrl = "media_url"
        case highlightLineStart = "highlight_line_start"
        case highlightLineEnd = "highlight_line_end"
    }
}

struct MobileErrorResponse: Codable, Equatable {
    let ok: Bool
    let error: String
}
