import Foundation
import Combine
import UIKit

@MainActor
public class DownloadManager: NSObject, ObservableObject {
    public static let shared = DownloadManager()

    @Published public var tasks: [DownloadTask] = []
    @Published public var activeCount: Int = 0
    @Published public var completedCount: Int = 0
    @Published public var totalSpeedString: String = "0 B/s"

    private var activeSessions: [UUID: [URLSessionDataTask]] = [:]
    private var speedTimer: Timer?
    private var lastBytesMap: [UUID: Int64] = [:]
    private let documentsURL: URL

    override public init() {
        self.documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        super.init()
        startSpeedMonitoring()
    }

    public func startDownload(url: URL, filename: String, segmentsCount: Int = 8) {
        let task = DownloadTask(url: url, filename: filename)
        tasks.insert(task, at: 0)
        task.state = .downloading
        updateCounts()

        Task {
            await probeAndExecute(task: task, segmentsCount: segmentsCount)
        }
    }

    private func probeAndExecute(task: DownloadTask, segmentsCount: Int) async {
        var probeReq = URLRequest(url: task.url)
        probeReq.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        probeReq.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        var supportsRange = false
        var totalLength: Int64 = -1

        if let (_, resp) = try? await URLSession.shared.data(for: probeReq),
           let http = resp as? HTTPURLResponse {
            if http.statusCode == 206 {
                supportsRange = true
                if let cr = http.value(forHTTPHeaderField: "Content-Range"), let slash = cr.lastIndex(of: "/") {
                    let totalStr = String(cr[cr.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
                    totalLength = Int64(totalStr) ?? -1
                }
            } else if http.statusCode == 200 {
                if let ar = http.value(forHTTPHeaderField: "Accept-Ranges"), ar.lowercased() == "bytes" {
                    supportsRange = true
                }
                totalLength = http.expectedContentLength
            }
        }

        task.totalBytes = totalLength
        let destination = documentsURL.appendingPathComponent(task.filename)
        task.localFileURL = destination

        // Pre-allocate file if size known
        if totalLength > 0 {
            FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: nil)
            if let fileHandle = try? FileHandle(forWritingTo: destination) {
                try? fileHandle.truncate(atOffset: UInt64(totalLength))
                try? fileHandle.close()
            }
        }

        let numSegments = supportsRange && totalLength > 1024 * 1024 ? min(16, max(1, segmentsCount)) : 1
        let segmentSize = totalLength > 0 ? (totalLength / Int64(numSegments)) : -1

        var segs: [SegmentProgress] = []
        for i in 0..<numSegments {
            let start = totalLength > 0 ? Int64(i) * segmentSize : 0
            let end = (i == numSegments - 1 && totalLength > 0) ? (totalLength - 1) : (start + segmentSize - 1)
            segs.append(SegmentProgress(id: i, startByte: start, endByte: end, currentByte: start, isFinished: false))
        }
        task.segments = segs

        if numSegments > 1 {
            await downloadParallel(task: task, destination: destination)
        } else {
            await downloadSingle(task: task, destination: destination)
        }
    }

    private func downloadParallel(task: DownloadTask, destination: URL) async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<task.segments.count {
                let seg = task.segments[i]
                group.addTask {
                    await self.downloadSegment(task: task, segIndex: i, destination: destination)
                }
            }
        }

        // Completion check
        if task.downloadedBytes >= task.totalBytes && task.totalBytes > 0 {
            task.state = .completed
            task.speedString = "Finished"
            notifyCompleted(task: task)
        } else if task.state != .paused {
            task.state = .failed
            task.errorMessage = "انقطع التحميل قبل الاكتمال"
        }
        updateCounts()
    }

    private func downloadSegment(task: DownloadTask, segIndex: Int, destination: URL) async {
        let seg = task.segments[segIndex]
        var req = URLRequest(url: task.url)
        req.setValue("bytes=\(seg.startByte)-\(seg.endByte)", forHTTPHeaderField: "Range")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (asyncBytes, resp) = try? await URLSession.shared.bytes(for: req),
              let http = resp as? HTTPURLResponse, (http.statusCode == 200 || http.statusCode == 206) else {
            return
        }

        guard let handle = try? FileHandle(forWritingTo: destination) else { return }
        try? handle.seek(toOffset: UInt64(seg.startByte))

        var currentOffset = seg.startByte
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    currentOffset += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)

                    let written = currentOffset
                    await MainActor.run {
                        task.segments[segIndex].currentByte = written
                        let totalDone = task.segments.reduce(0) { $0 + max(0, $1.currentByte - $1.startByte) }
                        task.downloadedBytes = totalDone
                    }
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                currentOffset += Int64(buffer.count)
                let written = currentOffset
                await MainActor.run {
                    task.segments[segIndex].currentByte = written
                    task.segments[segIndex].isFinished = true
                    let totalDone = task.segments.reduce(0) { $0 + max(0, $1.currentByte - $1.startByte) }
                    task.downloadedBytes = totalDone
                }
            }
            try handle.close()
        } catch {
            try? handle.close()
        }
    }

    private func downloadSingle(task: DownloadTask, destination: URL) async {
        var req = URLRequest(url: task.url)
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        guard let (asyncBytes, resp) = try? await URLSession.shared.bytes(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            task.state = .failed
            task.errorMessage = "فشل الاتصال بالخادم"
            updateCounts()
            return
        }

        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: destination) else { return }

        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        do {
            for try await byte in asyncBytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try handle.write(contentsOf: buffer)
                    let added = Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    task.downloadedBytes += added
                }
            }
            if !buffer.isEmpty {
                try handle.write(contentsOf: buffer)
                task.downloadedBytes += Int64(buffer.count)
            }
            try handle.close()
            task.state = .completed
            task.speedString = "Finished"
            notifyCompleted(task: task)
        } catch {
            try? handle.close()
            task.state = .failed
        }
        updateCounts()
    }

    public func pauseTask(_ task: DownloadTask) {
        task.state = .paused
        updateCounts()
    }

    public func resumeTask(_ task: DownloadTask) {
        task.state = .downloading
        updateCounts()
        Task {
            if let dest = task.localFileURL {
                await downloadParallel(task: task, destination: dest)
            }
        }
    }

    public func deleteTask(_ task: DownloadTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks.remove(at: idx)
        }
        if let file = task.localFileURL {
            try? FileManager.default.removeItem(at: file)
        }
        updateCounts()
    }

    private func updateCounts() {
        activeCount = tasks.filter { $0.state == .downloading }.count
        completedCount = tasks.filter { $0.state == .completed }.count
    }

    private func startSpeedMonitoring() {
        speedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            var totalSpeed: Int64 = 0
            for task in self.tasks where task.state == .downloading {
                let last = self.lastBytesMap[task.id] ?? 0
                let current = task.downloadedBytes
                let speed = max(0, current - last)
                self.lastBytesMap[task.id] = current
                task.speedString = "\(DownloadTask.formatBytes(speed))/s"
                totalSpeed += speed
            }
            self.totalSpeedString = "\(DownloadTask.formatBytes(totalSpeed))/s"
        }
    }

    private func notifyCompleted(task: DownloadTask) {
        let content = UNMutableNotificationContent()
        content.title = "اكتمل التحميل بنجاح ⚡"
        content.body = task.filename
        content.sound = .default
        let req = UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }
}
