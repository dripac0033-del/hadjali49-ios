import Foundation

public struct MediaItem: Identifiable, Hashable {
    public let id: String
    public var title: String
    public var channel: String
    public var duration: String
    public var platform: String
    public var webUrl: String
    public var thumbnailUrl: String?
    public var directAudioUrl: String?
    public var directVideoUrl: String?

    public init(id: String, title: String, channel: String, duration: String, platform: String, webUrl: String, thumbnailUrl: String? = nil) {
        self.id = id
        self.title = title
        self.channel = channel
        self.duration = duration
        self.platform = platform
        self.webUrl = webUrl
        self.thumbnailUrl = thumbnailUrl
        self.directAudioUrl = nil
        self.directVideoUrl = nil
    }
}

public struct ExtractedMedia {
    public let title: String
    public let downloadUrl: String
    public let format: String
    public let quality: String
    public let platform: String

    public init(title: String, downloadUrl: String, format: String, quality: String, platform: String) {
        self.title = title
        self.downloadUrl = downloadUrl
        self.format = format
        self.quality = quality
        self.platform = platform
    }
}
