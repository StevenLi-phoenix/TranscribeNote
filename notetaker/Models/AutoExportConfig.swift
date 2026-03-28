import Foundation

/// Configuration for the auto-export pipeline that runs after recording + summary complete.
nonisolated struct AutoExportConfig: Codable, Sendable, Equatable {
    var isEnabled: Bool = false
    var actions: [ExportAction] = []

    static func fromUserDefaults() -> AutoExportConfig {
        guard let data = UserDefaults.standard.data(forKey: "autoExportConfig"),
              let config = try? JSONDecoder().decode(AutoExportConfig.self, from: data) else {
            return AutoExportConfig()
        }
        return config
    }

    func saveToUserDefaults() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "autoExportConfig")
        }
    }
}

nonisolated enum ExportAction: Codable, Sendable, Equatable, Identifiable {
    case writeFile(WriteFileOptions)
    case copyTranscript
    case webhook(WebhookOptions)

    var id: String {
        switch self {
        case .writeFile: return "writeFile"
        case .copyTranscript: return "copyTranscript"
        case .webhook: return "webhook"
        }
    }

    var displayName: String {
        switch self {
        case .writeFile: return "Write to File"
        case .copyTranscript: return "Copy Transcript"
        case .webhook: return "Send Webhook"
        }
    }

    var icon: String {
        switch self {
        case .writeFile: return "doc.text"
        case .copyTranscript: return "doc.on.clipboard"
        case .webhook: return "arrow.up.forward.app"
        }
    }
}

nonisolated struct WriteFileOptions: Codable, Sendable, Equatable {
    var directoryPath: String = ""
    var filenameTemplate: String = "{{title}}_{{date}}"
    var includeTranscript: Bool = true
    var includeSummary: Bool = true
}

nonisolated struct WebhookOptions: Codable, Sendable, Equatable {
    var url: String = ""
    var method: String = "POST"
    var includeTranscript: Bool = true
    var includeSummary: Bool = true
    var secretHeader: String = ""
}
