import SwiftUI

public struct SocialMP3View: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @State private var query: String = ""
    @State private var results: [MediaItem] = []
    @State private var totalFound: Int = 0
    @State private var isLoading: Bool = false
    @State private var statusMessage: String = "ابحث عن أي أغنية، فنان، أو فيديو..."
    @State private var selectedPlayerMedia: (title: String, url: URL)? = nil
    @State private var activeResolvingId: String? = nil

    public var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255).ignoresSafeArea()

            VStack(spacing: 12) {
                // Search Input Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("ابحث (مثال: Didine Canon 16 - Skati)...", text: $query, onCommit: executeSearch)
                        .foregroundColor(.white)
                        .autocapitalization(.none)

                    if !query.isEmpty {
                        Button(action: { query = ""; results = [] }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }

                    Button(action: executeSearch) {
                        Text("بحث")
                            .font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(red: 6/255, green: 182/255, blue: 212/255))
                            .foregroundColor(.black)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(red: 30/255, green: 41/255, blue: 59/255))
                .cornerRadius(14)
                .padding(.horizontal)
                .padding(.top, 8)

                // Status info
                HStack {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                    if totalFound > 0 {
                        Text("\(totalFound) نتيجة")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal)

                // Results List
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                        .scaleEffect(1.3)
                    Text("جاري استخراج وبحث التسجيلات بأقصى سرعة...")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                    Spacer()
                } else if results.isEmpty {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 46))
                            .foregroundColor(.gray.opacity(0.6))
                        Text("مكتبة الوسائط والاستوديو العالمي")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(results) { item in
                                socialCard(item: item)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .navigationTitle("Social & MP3")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(get: {
            selectedPlayerMedia.map { IdentifiableMedia(title: $0.title, url: $0.url) }
        }, set: { val in
            selectedPlayerMedia = val.map { ($0.title, $0.url) }
        })) { media in
            DedicatedPlayerView(title: media.title, mediaURL: media.url)
        }
    }

    private func executeSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        statusMessage = "جاري الاتصال بقاعدة بيانات الاستوديو ويوتيوب..."

        Task {
            let res = await SocialMediaExtractor.shared.searchMedia(query: query)
            await MainActor.run {
                self.results = res.items
                self.totalFound = res.totalFound
                self.isLoading = false
                self.statusMessage = res.items.isEmpty ? "لم يتم العثور على نتائج مباشرة" : "تم العثور على النتائج بنجاح"
            }
        }
    }

    private func socialCard(item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 15/255, green: 23/255, blue: 42/255))
                        .frame(width: 54, height: 54)
                    Image(systemName: item.platform == "Master Audio" ? "opticaldisc" : "play.rectangle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(item.platform == "Master Audio" ? .cyan : .red)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack {
                        Text(item.channel)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(item.platform)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.2))
                            .foregroundColor(.cyan)
                            .cornerRadius(6)
                    }
                }
            }

            // Buttons: Preview (استماع), MP3 320k, MP4
            HStack(spacing: 8) {
                Button(action: { playPreview(item: item) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("استماع")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 16/255, green: 185/255, blue: 129/255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 16/255, green: 185/255, blue: 129/255).opacity(0.15))
                    .cornerRadius(8)
                }

                Button(action: { startDownloadMedia(item: item, audioOnly: true) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note")
                        Text("MP3 320k")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.cyan)
                    .cornerRadius(8)
                }

                Button(action: { startDownloadMedia(item: item, audioOnly: false) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "film")
                        Text("MP4")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(red: 59/255, green: 130/255, blue: 246/255).opacity(0.3))
                    .cornerRadius(8)
                }
            }
        }
        .padding(12)
        .background(Color(red: 30/255, green: 41/255, blue: 59/255))
        .cornerRadius(14)
    }

    private func playPreview(item: MediaItem) {
        Task {
            if let media = try? await SocialMediaExtractor.shared.resolveMediaStream(item: item, audioOnly: true),
               let streamUrl = URL(string: media.downloadUrl) {
                await MainActor.run {
                    self.selectedPlayerMedia = (media.title, streamUrl)
                }
            }
        }
    }

    private func startDownloadMedia(item: MediaItem, audioOnly: Bool) {
        Task {
            if let media = try? await SocialMediaExtractor.shared.resolveMediaStream(item: item, audioOnly: audioOnly),
               let streamUrl = URL(string: media.downloadUrl) {
                await MainActor.run {
                    self.downloadManager.startDownload(url: streamUrl, filename: media.title, segmentsCount: 8)
                }
            }
        }
    }
}
