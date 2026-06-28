import SwiftUI
import AVFoundation
import Speech

/// 语音录制器：长按麦克风录音 → 输出本地 m4a 文件 URL + 时长。
@MainActor
final class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var elapsed: TimeInterval = 0
    /// 微信式上滑取消：手指上滑超过阈值时置 true，松手则丢弃。
    @Published var canceling = false

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
            canceling = false
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
        canceling = false
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = fileURL, dur >= 1 else { return nil }
        return (url, max(1, dur))
    }

    func cancel() {
        timer?.invalidate(); timer = nil
        recorder?.stop()
        isRecording = false
        canceling = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }
}

/// 设备端语音转文字（中文）。供「羊皮纸助手」把语音指令转成文本。
enum SpeechTranscriber {
    private final class Once {
        private let lock = NSLock()
        private var done = false
        func run(_ block: () -> Void) {
            lock.lock(); defer { lock.unlock() }
            if !done { done = true; block() }
        }
    }

    /// 转写本地音频文件，返回识别文本；无权限/不可用/失败返回 nil。
    static func transcribe(_ url: URL) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized,
                      let rec = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
                      rec.isAvailable else {
                    cont.resume(returning: nil); return
                }
                let once = Once()
                let req = SFSpeechURLRecognitionRequest(url: url)
                rec.recognitionTask(with: req) { result, error in
                    if let result, result.isFinal {
                        let text = result.bestTranscription.formattedString
                        once.run { cont.resume(returning: text.isEmpty ? nil : text) }
                    } else if error != nil {
                        once.run { cont.resume(returning: nil) }
                    }
                }
            }
        }
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

/// 微信式「按住 说话」条：长按录音，手指上滑取消，松手回调音频。
/// recorder 由父视图持有（@StateObject），以便同屏的 VoiceRecordingHUD 同步刷新。
struct HoldToTalkBar: View {
    @ObservedObject var recorder: AudioRecorder
    var idleLabel: String                       // "按住 说话"
    var onFinish: (URL, Int) -> Void            // 录好的音频（已过滤 <1s）

    private var title: String {
        guard recorder.isRecording else { return idleLabel }
        return recorder.canceling ? "松开 取消" : "松开 发送"
    }

    var body: some View {
        Text(title)
            .font(FlowTheme.body(15))
            .foregroundStyle(recorder.canceling ? .red : FlowTheme.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 22)
                .fill(recorder.isRecording ? FlowTheme.sage.opacity(0.55) : Color.white.opacity(0.9)))
            .sketchBorder(22, width: 1.4, seed: 42)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if !recorder.isRecording { recorder.start() }
                        recorder.canceling = v.translation.height < -70
                    }
                    .onEnded { _ in
                        let cancel = recorder.canceling
                        if cancel { recorder.cancel() }
                        else if let (url, secs) = recorder.stop() { onFinish(url, secs) }
                    }
            )
    }
}

/// 录音时居中悬浮的 HUD（微信式：麦克风 + 取消提示 + 计时）。挂在页面顶层 ZStack/overlay。
struct VoiceRecordingHUD: View {
    @ObservedObject var recorder: AudioRecorder

    var body: some View {
        if recorder.isRecording {
            VStack(spacing: 14) {
                Image(systemName: recorder.canceling ? "xmark.circle.fill" : "mic.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(recorder.canceling ? .red : .white)
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { i in
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: 4, height: [10, 20, 30, 24, 14, 26, 12][i])
                    }
                }
                .opacity(recorder.canceling ? 0.25 : 1)
                Text(String(format: "%d:%02d", Int(recorder.elapsed) / 60, Int(recorder.elapsed) % 60))
                    .font(FlowTheme.caption(13)).foregroundStyle(.white.opacity(0.8))
                Text(recorder.canceling ? "松开手指，取消发送" : "手指上滑，取消发送")
                    .font(FlowTheme.caption(12)).foregroundStyle(.white.opacity(0.9))
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.72)))
            .transition(.opacity)
        }
    }
}

/// 聊天里的语音气泡（微信式：宽度随时长、喇叭波纹、点按播放）。content 形如 "url|seconds"。
struct VoiceMessageBubble: View {
    let content: String
    let mine: Bool
    var seed: UInt64 = 30
    @ObservedObject private var playback = VoicePlayback.shared

    private var url: String { content.components(separatedBy: "|").first ?? content }
    private var seconds: Int { Int(content.components(separatedBy: "|").last ?? "") ?? 0 }
    private var isPlaying: Bool { playback.playingURL == url }
    private var fg: Color { mine ? FlowTheme.sageInk : FlowTheme.ink }
    /// 气泡宽度随时长增长（微信观感），封顶避免过宽。
    private var bubbleWidth: CGFloat { min(200, 64 + CGFloat(min(seconds, 60)) * 5) }

    private var speaker: some View {
        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "speaker.wave.2")
            .font(.system(size: 18)).foregroundStyle(fg)
            .scaleEffect(x: mine ? 1 : -1, y: 1)   // 对方的喇叭朝左
    }
    private var durationText: some View {
        Text("\(seconds)\u{2033}").font(FlowTheme.caption(13)).foregroundStyle(fg.opacity(0.85))
    }

    var body: some View {
        Button { playback.toggle(url) } label: {
            HStack(spacing: 8) {
                if mine { Spacer(minLength: 0); durationText; speaker }
                else { speaker; durationText; Spacer(minLength: 0) }
            }
            .frame(width: bubbleWidth)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .sketchCard(18, fill: mine ? FlowTheme.sage : Color(hex: 0xFCFAF4), seed: seed)
        }
        .buttonStyle(.plain)
    }
}
