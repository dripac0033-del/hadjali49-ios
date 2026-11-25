import SwiftUI

public struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var showAddLinkSheet: Bool = false
    @State private var inputUrl: String = ""
    @State private var selectedPlayerMedia: (title: String, url: URL)? = nil

    public var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header Stats Bar
                HStack(spacing: 12) {
                    statCard(title: "ACTIVE", value: "\(downloadManager.activeCount)", color: .cyan)
                    statCard(title: "TOTAL SPEED", value: downloadManager.totalSpeedString, color: Color(red: 16/255, green: 185/255, blue: 129/255))
                    statCard(title: "COMPLETED", value: "\(downloadManager.completedCount)", color: .indigo)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Downloads List
                if downloadManager.tasks.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("لا توجد تنزيلات حالية")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.gray)
                        Button(action: { showAddLinkSheet = true }) {
                            Text("+ إضافة رابط جديد")
                                .font(.system(size: 14, weight: .bold))
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.cyan)
                                .foregroundColor(.black)
                                .cornerRadius(12)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(downloadManager.tasks) { task in
                                downloadTaskCard(task: task)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("التنزيلات (Downloads)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddLinkSheet = true }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.cyan)
                }
            }
        }
        .sheet(isPresented: $showAddLinkSheet) {
            addLinkSheetView
        }
        .sheet(item: Binding(get: {
            selectedPlayerMedia.map { IdentifiableMedia(title: $0.title, url: $0.url) }
        }, set: { val in
            selectedPlayerMedia = val.map { ($0.title, $0.url) }
        })) { media in
            DedicatedPlayerView(title: media.title, mediaURL: media.url)
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.gray)
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 30/255, green: 41/255, blue: 59/255))
        .cornerRadius(14)
    }

    private func downloadTaskCard(task: DownloadTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(task.filename)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 6/255, green: 182/255, blue: 212/255))
                    .lineLimit(1)
                Spacer()
                Text(task.state.rawValue)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(stateColor(task.state).opacity(0.2))
                    .foregroundColor(stateColor(task.state))
                    .cornerRadius(8)
            }

            HStack {
                Text(task.formattedProgress)
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                Spacer()
                Text(task.speedString)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
            }

            // Continuous Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [.cyan, Color(red: 16/255, green: 185/255, blue: 129/255)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(task.progressFraction))
                }
            }
            .frame(height: 6)

            // 16-Segment Visualizer
            HStack(spacing: 3) {
                ForEach(task.segments) { seg in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(seg.isFinished ? Color(red: 16/255, green: 185/255, blue: 129/255) :
                                (seg.progressFraction > 0 ? Color.cyan : Color.gray.opacity(0.3)))
                        .frame(height: 6)
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button(action: { downloadManager.deleteTask(task) }) {
                    Text("DELETE")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.15))
                        .cornerRadius(10)
                }

                if task.state == .completed, let fileUrl = task.localFileURL {
                    Button(action: {
                        selectedPlayerMedia = (task.filename, fileUrl)
                    }) {
                        Text("OPEN FILE 🎧")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color(red: 16/255, green: 185/255, blue: 129/255))
                            .cornerRadius(10)
                    }
                } else if task.state == .downloading {
                    Button(action: { downloadManager.pauseTask(task) }) {
                        Text("PAUSE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(10)
                    }
                } else if task.state == .paused {
                    Button(action: { downloadManager.resumeTask(task) }) {
                        Text("RESUME")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.cyan)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(red: 30/255, green: 41/255, blue: 59/255))
        .cornerRadius(16)
    }

    private func stateColor(_ state: DownloadState) -> Color {
        switch state {
        case .downloading: return .cyan
        case .completed: return Color(red: 16/255, green: 185/255, blue: 129/255)
        case .paused: return .orange
        case .failed: return .red
        case .queued: return .gray
        }
    }

    private var addLinkSheetView: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("إضافة رابط للتحميل السريع")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)

                TextField("ضع رابط التحميل هنا (HTTP, MP4, MP3, Archive...)", text: $inputUrl)
                    .padding()
                    .background(Color(red: 30/255, green: 41/255, blue: 59/255))
                    .cornerRadius(12)
                    .foregroundColor(.white)
                    .autocapitalization(.none)

                Button(action: {
                    if let u = URL(string: inputUrl.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        let name = u.lastPathComponent.isEmpty ? "download_\(Int(Date().timeIntervalSince1970)).bin" : u.lastPathComponent
                        downloadManager.startDownload(url: u, filename: name)
                        showAddLinkSheet = false
                        inputUrl = ""
                    }
                }) {
                    Text("⚡ بدء التحميل الفائق")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.cyan)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }
                Spacer()
            }
            .padding()
        }
    }
}

struct IdentifiableMedia: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}
