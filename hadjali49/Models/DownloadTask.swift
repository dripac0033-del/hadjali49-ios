import Foundation

public enum DownloadState: String, Codable {
    case queued = "Queued"
    case downloading = "Downloading"
    case paused = "Paused"
    case completed = "Completed"
    case failed = "Failed"
}

public struct SegmentProgress: Identifiable, Codable {
    public var id: Int
    public var startByte: Int64
    public var endByte: Int64
    public var currentByte: Int64
    public var isFinished: Bool

    public var progressFraction: Double {
        let total = max(1, endByte - startByte + 1)
        let done = max(0, currentByte - startByte)
        return min(1.0, Double(done) / Double(total))
    }
}

public class DownloadTask: Identifiable, ObservableObject {
    public let id: UUID
    public let url: URL
    public let originalUrlString: String
    @Published public var filename: String
    @Published public var totalBytes: Int64
    @Published public var downloadedBytes: Int64
    @Published public var state: DownloadState
    @Published public var speedString: String
    @Published public var errorMessage: String?
    @Published public var localFileURL: URL?
    @Published public var segments: [SegmentProgress]
    public let createdAt: Date

    public init(id: UUID = UUID(), url: URL, filename: String, totalBytes: Int64 = -1) {
        self.id = id
        self.url = url
        self.originalUrlString = url.absoluteString
        self.filename = filename
        self.totalBytes = totalBytes
        self.downloadedBytes = 0
        self.state = .queued
        self.speedString = "0 B/s"
        self.errorMessage = nil
        self.localFileURL = nil
        self.segments = (0..<16).map { SegmentProgress(id: $0, startByte: 0, endByte: 0, currentByte: 0, isFinished: false) }
        self.createdAt = Date()
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else { return 0.0 }
        return min(1.0, max(0.0, Double(downloadedBytes) / Double(totalBytes)))
    }

    public var progressPercent: Int {
        return Int(progressFraction * 100)
    }

    public var formattedProgress: String {
        if totalBytes > 0 {
            return "\(Self.formatBytes(downloadedBytes)) / \(Self.formatBytes(totalBytes)) (\(progressPercent)%)"
        } else {
            return "\(Self.formatBytes(downloadedBytes)) (Unknown Size)"
        }
    }

    public static func formatBytes(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let units = ["B", "KB", "MB", "GB", "TB"]
        var b = Double(bytes)
        var i = 0
        while b >= 1024.0 && i < units.count - 1 {
            b /= 1024.0
            i += 1
        }
        return String(format: "%.1f %@", b, units[i])
    }
}
