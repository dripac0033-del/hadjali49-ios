import Foundation

public class SocialMediaExtractor {
    public static let shared = SocialMediaExtractor()

    private let pipedInstances = [
        "https://api.piped.private.coffee",
        "https://pipedapi.nosebs.ru",
        "https://piped-api.privacy.com.de",
        "https://pipedapi.owo.si",
        "https://piped-api.codespace.cz",
        "https://piped.video/api/v1"
    ]

    private init() {}

    public func searchMedia(query: String, page: Int = 0) async -> (items: [MediaItem], totalFound: Int) {
        async let archiveSearch = searchArchiveMasterAudio(query: query, page: page)
        async let ytSearch = searchYouTubeInnertube(query: query)

        let (archiveItems, total) = await archiveSearch
        let ytItems = page == 0 ? await ytSearch : []

        var combined: [MediaItem] = []
        combined.append(contentsOf: archiveItems)
        combined.append(contentsOf: ytItems)
        return (combined, total)
    }

    public func resolveMediaStream(item: MediaItem, audioOnly: Bool) async throws -> ExtractedMedia {
        if item.platform == "Master Audio" || item.webUrl.contains("archive.org") {
            if let resolved = try? await resolveArchiveItem(id: item.id, title: item.title, creator: item.channel, audioOnly: audioOnly) {
                return resolved
            }
        }

        if item.platform == "YouTube" || item.webUrl.contains("youtu") {
            if let resolved = try? await extractFromYouTube(url: item.webUrl, audioOnly: audioOnly) {
                return resolved
            }
        }

        throw NSError(domain: "SocialMediaExtractor", code: -1, userInfo: [NSLocalizedDescriptionKey: "تعذر استخراج مسار التحميل المباشر. يرجى اختيار ملف آخر."])
    }

    public func extractFromYouTube(url: String, audioOnly: Bool) async throws -> ExtractedMedia {
        guard let videoId = extractYouTubeId(url: url) else {
            throw NSError(domain: "SocialMediaExtractor", code: -2, userInfo: [NSLocalizedDescriptionKey: "معرف يوتيوب غير صالح"])
        }

        // 1. Fetch exact YouTube title via oEmbed
        var realTitle: String? = nil
        var authorName: String? = nil
        if let oembedUrl = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoId)&format=json") {
            var req = URLRequest(url: oembedUrl)
            req.timeoutInterval = 4.0
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                realTitle = json["title"] as? String
                authorName = json["author_name"] as? String
            }
        }

        let rawTitle = realTitle ?? "YouTube_\(videoId)"
        let cleanTitle = formatSongTitle(rawTitle: rawTitle, creator: authorName)

        // 2. Direct Piped Multi-Instance Stream extraction
        if let piped = await extractFromPiped(videoId: videoId, cleanTitle: cleanTitle, authorName: authorName, audioOnly: audioOnly) {
            return piped
        }

        // 3. Fallback search on Archive.org
        let searchTerms = cleanTitle
            .replacingOccurrences(of: "(?i)\\b(video|clip|music|audio|hd|4k|remastered|official|reaction)\\b", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if searchTerms.count > 2 {
            let (matches, _) = await searchArchiveMasterAudio(query: searchTerms, page: 0)
            if let topMatch = matches.first,
               let resolved = try? await resolveArchiveItem(id: topMatch.id, title: cleanTitle, creator: authorName, audioOnly: audioOnly) {
                return resolved
            }
        }

        throw NSError(domain: "SocialMediaExtractor", code: -3, userInfo: [NSLocalizedDescriptionKey: "تعذر استخراج البث المباشر. يرجى تجربة ملف آخر."])
    }

    private func extractFromPiped(videoId: String, cleanTitle: String, authorName: String?, audioOnly: Bool) async -> ExtractedMedia? {
        for base in pipedInstances {
            guard let url = URL(string: "\(base)/streams/\(videoId)") else { continue }
            var req = URLRequest(url: url)
            req.timeoutInterval = 4.0
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  let http = resp as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let respTitle = json["title"] as? String
            let respUploader = json["uploader"] as? String ?? authorName
            var finalTitle = cleanTitle
            if finalTitle.starts(with: "YouTube_"), let rTitle = respTitle, !rTitle.isEmpty {
                finalTitle = formatSongTitle(rawTitle: rTitle, creator: respUploader)
            }

            var targetUrl: String? = nil
            var targetQuality = audioOnly ? "320kbps Audio (Direct Stream)" : "HD Video (Direct Stream)"

            if audioOnly {
                if let audioStreams = json["audioStreams"] as? [[String: Any]], !audioStreams.isEmpty {
                    var bestBitrate: Int64 = -1
                    for asObj in audioStreams {
                        if let streamUrl = asObj["url"] as? String, !streamUrl.isEmpty {
                            let bitrate = (asObj["bitrate"] as? NSNumber)?.int64Value ?? 0
                            if bitrate > bestBitrate || targetUrl == nil {
                                bestBitrate = bitrate
                                targetUrl = streamUrl
                            }
                        }
                    }
                }

                if targetUrl == nil, let videoStreams = json["videoStreams"] as? [[String: Any]] {
                    for vs in videoStreams {
                        if let streamUrl = vs["url"] as? String, (vs["videoOnly"] as? Bool) != true {
                            targetUrl = streamUrl
                            break
                        }
                    }
                    if targetUrl == nil, let first = videoStreams.first, let streamUrl = first["url"] as? String {
                        targetUrl = streamUrl
                    }
                }
            } else {
                if let videoStreams = json["videoStreams"] as? [[String: Any]], !videoStreams.isEmpty {
                    for vs in videoStreams {
                        if let streamUrl = vs["url"] as? String, (vs["videoOnly"] as? Bool) != true {
                            targetUrl = streamUrl
                            let q = vs["quality"] as? String ?? "HD"
                            targetQuality = "\(q) Video"
                            if q.contains("720") || q.contains("1080") { break }
                        }
                    }
                    if targetUrl == nil, let first = videoStreams.first, let streamUrl = first["url"] as? String {
                        targetUrl = streamUrl
                    }
                }
            }

            if let validUrl = targetUrl, !validUrl.isEmpty {
                let ext = audioOnly ? ".mp3" : ".mp4"
                return ExtractedMedia(
                    title: "\(sanitizeFilename(finalTitle))\(ext)",
                    downloadUrl: validUrl,
                    format: audioOnly ? "MP3" : "MP4",
                    quality: targetQuality,
                    platform: "YouTube Turbo Stream"
                )
            }
        }
        return nil
    }

    private func searchArchiveMasterAudio(query: String, page: Int) async -> (items: [MediaItem], total: Int) {
        var cleanQ = query.replacingOccurrences(of: "[-_()\"'\\[\\]:]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanQ.isEmpty { cleanQ = query }

        let qParam = "(\(cleanQ)) AND mediatype:audio"
        guard let encodedQ = qParam.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ([], 0)
        }

        let rows = 35
        let pageParam = page + 1
        let urlStr = "https://archive.org/advancedsearch.php?q=\(encodedQ)&fl[]=identifier,title,creator,downloads,item_size,format&sort[]=downloads+desc&rows=\(rows)&page=\(pageParam)&output=json"
        guard let url = URL(string: urlStr) else { return ([], 0) }

        var req = URLRequest(url: url)
        req.timeoutInterval = 5.0
        req.setValue("hadjali49-iOS/2.2.0", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let respObj = root["response"] as? [String: Any] else {
            return ([], 0)
        }

        let numFound = respObj["numFound"] as? Int ?? 0
        var items: [MediaItem] = []

        if let docs = respObj["docs"] as? [[String: Any]] {
            for d in docs {
                guard let id = d["identifier"] as? String else { continue }
                let rawTitle = d["title"] as? String ?? id
                let creator = d["creator"] as? String ?? "Studio Recording"
                let clean = formatSongTitle(rawTitle: rawTitle, creator: creator)
                var item = MediaItem(
                    id: id,
                    title: clean,
                    channel: creator,
                    duration: "320kbps MP3",
                    platform: "Master Audio",
                    webUrl: "https://archive.org/details/\(id)",
                    thumbnailUrl: "https://archive.org/services/img/\(id)"
                )
                items.append(item)
            }
        }
        return (items, numFound)
    }

    private func resolveArchiveItem(id: String, title: String, creator: String?, audioOnly: Bool) async throws -> ExtractedMedia {
        guard let metaUrl = URL(string: "https://archive.org/metadata/\(id)") else {
            throw NSError(domain: "Archive", code: -4, userInfo: nil)
        }

        var req = URLRequest(url: metaUrl)
        req.timeoutInterval = 5.0
        req.setValue("hadjali49-iOS/2.2.0", forHTTPHeaderField: "User-Agent")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]] else {
            throw NSError(domain: "Archive", code: -5, userInfo: nil)
        }

        var candidateFile: String? = nil
        var candidateFormat: String? = nil

        for f in files {
            guard let name = f["name"] as? String else { continue }
            let lower = name.lowercased()
            if audioOnly {
                if lower.hasSuffix(".mp3") {
                    candidateFile = name
                    candidateFormat = "MP3"
                    break
                }
            } else {
                if lower.hasSuffix(".mp4") {
                    candidateFile = name
                    candidateFormat = "MP4"
                    break
                }
            }
        }

        if candidateFile == nil {
            for f in files {
                guard let name = f["name"] as? String else { continue }
                let lower = name.lowercased()
                if audioOnly && (lower.hasSuffix(".m4a") || lower.hasSuffix(".ogg") || lower.hasSuffix(".flac")) {
                    candidateFile = name
                    candidateFormat = "Audio"
                    break
                }
            }
        }

        guard let chosenName = candidateFile else {
            throw NSError(domain: "Archive", code: -6, userInfo: [NSLocalizedDescriptionKey: "لم يتم العثور على ملف وسائط مباشر"])
        }

        let rawDl = "https://archive.org/download/\(id)/\(chosenName)"
        let dlUrl = rawDl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawDl
        let ext = audioOnly ? ".mp3" : ".mp4"

        return ExtractedMedia(
            title: "\(sanitizeFilename(title))\(ext)",
            downloadUrl: dlUrl,
            format: candidateFormat ?? (audioOnly ? "MP3" : "MP4"),
            quality: audioOnly ? "Master Studio 320k" : "HD Video",
            platform: "Archive.org"
        )
    }

    private func searchYouTubeInnertube(query: String) async -> [MediaItem] {
        guard let searchUrl = URL(string: "https://www.youtube.com/youtubei/v1/search") else { return [] }
        var req = URLRequest(url: searchUrl)
        req.httpMethod = "POST"
        req.timeoutInterval = 5.0
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "query": query,
            "context": [
                "client": [
                    "clientName": "WEB",
                    "clientVersion": "2.20231201.01.00",
                    "hl": "ar",
                    "gl": "DZ"
                ]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return [] }
        req.httpBody = bodyData

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let str = String(data: data, encoding: .utf8) else {
            return []
        }

        var results: [MediaItem] = []
        let pattern = "\"videoId\":\"([a-zA-Z0-9_-]{11})\".*?\"title\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}\\].*?\"ownerText\":\\{\"runs\":\\[\\{\"text\":\"(.*?)\"\\}\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let matches = regex.matches(in: str, options: [], range: NSRange(location: 0, length: str.utf16.count))

        var seen = Set<String>()
        for m in matches {
            if let vidRange = Range(m.range(at: 1), in: str),
               let titleRange = Range(m.range(at: 2), in: str),
               let authorRange = Range(m.range(at: 3), in: str) {
                let vid = String(str[vidRange])
                let title = String(str[titleRange])
                let author = String(str[authorRange])

                if seen.insert(vid).inserted {
                    let clean = formatSongTitle(rawTitle: title, creator: author)
                    let item = MediaItem(
                        id: vid,
                        title: clean,
                        channel: author,
                        duration: "YouTube",
                        platform: "YouTube",
                        webUrl: "https://www.youtube.com/watch?v=\(vid)",
                        thumbnailUrl: "https://i.ytimg.com/vi/\(vid)/hqdefault.jpg"
                    )
                    results.append(item)
                    if results.count >= 25 { break }
                }
            }
        }
        return results
    }

    public func extractYouTubeId(url: String) -> String? {
        let pattern = "(?:v=|/v/|youtu\\.be/|/embed/|/shorts/|\\?v=)([^&?\\s\"'>]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = NSString(string: url)
        if let match = regex.firstMatch(in: url, options: [], range: NSRange(location: 0, length: ns.length)) {
            return ns.substring(with: match.range(at: 1))
        }
        return nil
    }

    public func formatSongTitle(rawTitle: String, creator: String?) -> String {
        var cleaned = rawTitle
            .replacingOccurrences(of: "(?i)\\s*[\\(\\[]\\s*(official\\s+video|official\\s+music\\s+video|official\\s+audio|video\\s+clip|clip\\s+officiel|remastered|4k|hd|lyrics|lyric\\s+video|audio|hq|1080p|720p|visualizer|reaction|boussadat\\s+reaction|boussadat|20\\d\\d)\\s*[\\)\\]]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)\\b(official\\s+video|clip\\s+officiel|music\\s+video|remastered|4k\\s+uhd|reaction|boussadat)\\b", with: "", options: .regularExpression)
            .replacingOccurrences(of: "[\\|\"']", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if cleaned.hasSuffix("-") || cleaned.hasSuffix("_") {
            cleaned = String(cleaned.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let c = creator?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty,
           c.lowercased() != "studio recording", c.lowercased() != "creator" {
            let cLower = c.lowercased()
            let isJunk = cLower.contains("reaction") || cLower.contains("react") ||
                         cLower.contains("mg16") || cLower.contains("boussada") ||
                         cLower.contains("beats") || cLower.contains("channel")
            if !isJunk && !cleaned.lowercased().contains(cLower) {
                cleaned = "\(c) - \(cleaned)"
            }
        }
        return cleaned.isEmpty ? "Audio Track" : cleaned
    }

    public func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "download" : cleaned
    }
}
