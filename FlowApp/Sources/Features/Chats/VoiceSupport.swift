import SwiftUI
import AVFoundation

/// 语音录制器：长按麦克风录音 → 输出本地 m4a 文件 URL + 时长。
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private(set) var fileURL: URL?

    /// 请求权限并开始录音。
    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            guard granted else { return }
            Task { @MainActor in self?.beginRecording() }
        }
    }

    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.record()
            recorder = rec
            fileURL = url
            isRecording = true
            elapsed = 0
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder else { return }
                    self.elapsed = r.currentTime
                }
            }
        } catch {
            isRecording = false
        }
    }

    /// 停止并返回（文件 URL，秒数）；时长不足 1 秒视为取消。
    @discardableResult
    func stop() -> (URL, Int)? {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        let dur = Int(elapsed.rounded())
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = fileURL, dur >= 1 else { return nil }
        return (url, max(1, dur))
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }
}

/// 单例播放器：保证同一时刻只播一条语音。
@MainActor
final class VoicePlayback: NSObject, ObservableObject {
    static let shared = VoicePlayback()
    @Published var playingURL: String?
    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func toggle(_ urlString: String) {
        if playingURL == urlString { stop(); return }
        guard let url = URL(string: urlString) else { return }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        player = p
        playingURL = urlString
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        p.play()
    }

    func stop() {
        player?.pause(); player = nil
        playingURL = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
    }
}

/// 聊天里的语音气泡（远端 URL 播放）。content 形如 "url|seconds"。
struct VoiceMessageBubble: View {
    let content: String
    let mine: Bool
    var seed: UInt64 = 30
    @ObservedObject private var playback = VoicePlayback.shared

    private var url: String { content.components(separatedBy: "|").first ?? content }
    private var seconds: Int { Int(content.components(separatedBy: "|").last ?? "") ?? 0 }
    private var isPlaying: Bool { playback.playingURL == url }
    private var fg: Color { mine ? FlowTheme.sageInk : FlowTheme.teal }

    var body: some View {
        Button { playback.toggle(url) } label: {
            HStack(spacing: 10) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26)).foregroundStyle(fg)
                HStack(spacing: 2) {
                    ForEach(0..<22, id: \.self) { i in
                        Capsule().fill(fg.opacity(0.8)).frame(width: 2.5, height: waveHeight(i))
                    }
                }
                Text("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
                    .font(FlowTheme.caption(11)).foregroundStyle(fg.opacity(0.85))
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .sketchCard(18, fill: mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: seed)
        }
        .buttonStyle(.plain)
    }

    private func waveHeight(_ i: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 12, 20, 14, 8, 18, 24, 10, 16, 22, 9, 14]
        return pattern[i % pattern.count]
    }
}
