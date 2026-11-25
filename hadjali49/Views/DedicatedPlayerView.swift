import SwiftUI
import AVKit

public struct DedicatedPlayerView: View {
    public let title: String
    public let mediaURL: URL
    @Environment(\.dismiss) private var dismiss

    @State private var player: AVPlayer?
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0.0
    @State private var duration: Double = 1.0
    @State private var speed: Float = 1.0
    @State private var isLooping: Bool = false
    @State private var timeObserverToken: Any?
    @State private var showShareSheet: Bool = false

    private let speeds: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    public var body: some View {
        ZStack {
            Color(red: 15/255, green: 23/255, blue: 42/255)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                // Top Bar
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Text("مشغل استوديو hadjali49")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(red: 6/255, green: 182/255, blue: 212/255))
                    Spacer()
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundColor(.cyan)
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Center Album Art or Video
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 30/255, green: 41/255, blue: 59/255))
                        .frame(width: 240, height: 240)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(Color(red: 6/255, green: 182/255, blue: 212/255).opacity(0.3), lineWidth: 1.5)
                        )

                    VStack(spacing: 12) {
                        Image(systemName: "headphones")
                            .font(.system(size: 72))
                            .foregroundColor(Color(red: 6/255, green: 182/255, blue: 212/255))
                        Text("320kbps Master Audio")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }

                VStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal)

                    Text(formatTime(currentTime) + " / " + formatTime(duration))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.gray)
                }

                // Scrubber Slider
                VStack(spacing: 4) {
                    Slider(value: Binding(get: {
                        currentTime
                    }, set: { newTime in
                        currentTime = newTime
                        seek(to: newTime)
                    }), in: 0...max(1.0, duration))
                    .accentColor(Color(red: 6/255, green: 182/255, blue: 212/255))
                    .padding(.horizontal)

                    HStack {
                        Text(formatTime(currentTime))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                        Spacer()
                        Text(formatTime(duration))
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                    }
                    .padding(.horizontal, 24)
                }

                // Controls: Rewind, Play/Pause, Forward
                HStack(spacing: 36) {
                    Button(action: { seekRelative(-10) }) {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }

                    Button(action: togglePlayPause) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [Color(red: 6/255, green: 182/255, blue: 212/255), Color(red: 59/255, green: 130/255, blue: 246/255)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 70, height: 70)
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }

                    Button(action: { seekRelative(10) }) {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 26))
                            .foregroundColor(.white)
                    }
                }

                // Speed & Loop bar
                HStack(spacing: 24) {
                    Button(action: cycleSpeed) {
                        Text("\(String(format: "%.2fx", speed))")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color(red: 30/255, green: 41/255, blue: 59/255))
                            .cornerRadius(12)
                            .foregroundColor(.cyan)
                    }

                    Button(action: { isLooping.toggle() }) {
                        Image(systemName: isLooping ? "repeat.1" : "repeat")
                            .font(.system(size: 16, weight: .bold))
                            .padding(10)
                            .background(isLooping ? Color.cyan.opacity(0.3) : Color(red: 30/255, green: 41/255, blue: 59/255))
                            .cornerRadius(12)
                            .foregroundColor(isLooping ? .cyan : .gray)
                    }
                }

                Spacer()
            }
            .padding(.vertical)
        }
        .onAppear(perform: setupPlayer)
        .onDisappear(perform: teardownPlayer)
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: [mediaURL])
        }
    }

    private func setupPlayer() {
        let p = AVPlayer(url: mediaURL)
        self.player = p
        p.play()
        isPlaying = true

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            self.currentTime = time.seconds
            if let item = p.currentItem {
                let d = item.duration.seconds
                if !d.isNaN && d > 0 {
                    self.duration = d
                }
            }
        }

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { _ in
            if self.isLooping {
                self.seek(to: 0)
                self.player?.play()
            } else {
                self.isPlaying = false
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
        } else {
            p.play()
            p.rate = speed
        }
        isPlaying.toggle()
    }

    private func seek(to seconds: Double) {
        let cm = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: cm)
    }

    private func seekRelative(_ offset: Double) {
        let target = max(0, min(duration, currentTime + offset))
        seek(to: target)
    }

    private func cycleSpeed() {
        if let idx = speeds.firstIndex(of: speed) {
            let nextIdx = (idx + 1) % speeds.count
            speed = speeds[nextIdx]
        } else {
            speed = 1.0
        }
        if isPlaying {
            player?.rate = speed
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

public struct ActivityView: UIViewControllerRepresentable {
    public let activityItems: [Any]

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
