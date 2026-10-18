import Foundation
import AppKit
import AVFoundation

/// 拟物声学与触控板物理触感反馈引擎
/// 严格遵循 docs/macos.md §3.4 与 docs/ecosystem.md §4.4 规范：
/// 1. 机械相机快门声 (Shutter Click): 1200Hz + 800Hz 双脉冲闭合音
/// 2. 纸张翻动扑通声 (Paper Flip): 140Hz -> 45Hz 低频沉稳音
/// 3. 金属微触感声 (Tink): 2400Hz -> 1200Hz 轻敲音
/// 4. 触控板震动反馈 (NSHapticFeedbackManager): alignment / levelChange
@MainActor
public final class AudioFeedback {
    public static let shared = AudioFeedback()

    public static let soundEnabledKey = "looseleaf_sound_enabled"
    public static let hapticsEnabledKey = "looseleaf_haptics_enabled"

    private var playerPools: [String: [AVAudioPlayer]] = [:]
    private var poolIndices: [String: Int] = [:]
    private let poolSize: Int = 4

    public var isSoundEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.soundEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.soundEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.soundEnabledKey)
        }
    }

    public var isHapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.hapticsEnabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.hapticsEnabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.hapticsEnabledKey)
        }
    }

    private init() {
        preloadSynthesizedAudio()
    }

    // MARK: - 公开拟物反馈接口

    /// 机械相机快门声 + 触控板对齐震动（用于：新增记录落库、暗房相片上传完成、设备配对成功）
    public func playShutter() {
        if isHapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        guard isSoundEnabled else { return }
        playSound(named: "shutter")
    }

    /// 120g 重磅纸张翻动声（用于：翻阅画卷等特定拟物场景）
    /// 注意：常规页面切换或标签点击严禁触发触控板 levelChange，避免造成 macOS 物理点击后的二次顿挫与粘滞感
    public func playPaperFlip() {
        guard isSoundEnabled else { return }
        playSound(named: "paper_flip")
    }

    /// 轻微金属微触敲击声（用于：切换模式、勾选标签、点击选项）
    /// 注意：常规交互不触发硬件触控板震动，保留 Mac 原生触控板物理级清脆手感
    public func playTink() {
        guard isSoundEnabled else { return }
        playSound(named: "tink")
    }

    // MARK: - 音频加载与零依赖内存 WAV 合成

    private func playSound(named name: String) {
        guard let pool = playerPools[name], !pool.isEmpty else { return }
        let idx = poolIndices[name, default: 0]
        let player = pool[idx]
        player.currentTime = 0
        player.play()
        poolIndices[name] = (idx + 1) % pool.count
    }

    private func preloadSynthesizedAudio() {
        let names = ["shutter", "paper_flip", "tink"]
        for name in names {
            var pool: [AVAudioPlayer] = []
            let audioData: Data?
            if let url = locateBundledAudio(named: name) {
                audioData = try? Data(contentsOf: url)
            } else {
                audioData = synthesizeWAVData(for: name)
            }

            if let audioData {
                for _ in 0..<poolSize {
                    if let player = try? AVAudioPlayer(data: audioData) {
                        player.prepareToPlay()
                        pool.append(player)
                    }
                }
            }
            playerPools[name] = pool
            poolIndices[name] = 0
        }
    }

    private func locateBundledAudio(named name: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.module.url(forResource: name, withExtension: "wav") {
            return url
        }
        #endif
        return Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "Audio")
            ?? Bundle.main.url(forResource: name, withExtension: "wav")
    }

    private func synthesizeWAVData(for name: String) -> Data? {
        let sampleRate = 44100
        var samples: [Float] = []

        switch name {
        case "shutter":
            let count = Int(Double(sampleRate) * 0.065)
            samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                var val = 0.0
                if t < 0.015 {
                    let freq = 1200.0 * pow(0.3, t / 0.015)
                    let env = 0.25 * pow(0.001 / 0.25, t / 0.015)
                    val += env * sin(2.0 * .pi * freq * t)
                }
                if t >= 0.035 && t < 0.053 {
                    let dt = t - 0.035
                    let freq = 800.0 * pow(0.3, dt / 0.018)
                    let env = 0.20 * pow(0.001 / 0.20, dt / 0.018)
                    val += env * sin(2.0 * .pi * freq * dt)
                }
                samples[i] = Float(val)
            }
        case "paper_flip":
            let count = Int(Double(sampleRate) * 0.07)
            samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                if t < 0.06 {
                    let freq = 140.0 * pow(45.0 / 140.0, t / 0.06)
                    let env = 0.16 * pow(0.001 / 0.16, t / 0.06)
                    samples[i] = Float(env * sin(2.0 * .pi * freq * t))
                }
            }
        default: // "tink"
            let count = Int(Double(sampleRate) * 0.04)
            samples = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                if t < 0.03 {
                    let freq = 2400.0 * pow(1200.0 / 2400.0, t / 0.03)
                    let env = 0.10 * pow(0.001 / 0.10, t / 0.03)
                    samples[i] = Float(env * sin(2.0 * .pi * freq * t))
                }
            }
        }

        return encodePCM16WAV(samples: samples, sampleRate: sampleRate)
    }

    private func encodePCM16WAV(samples: [Float], sampleRate: Int) -> Data {
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate * Int(numChannels) * Int(bitsPerSample / 8))
        let blockAlign = UInt16(numChannels * (bitsPerSample / 8))
        let dataSize = UInt32(samples.count * 2)
        let chunkSize = 36 + dataSize

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: chunkSize.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        let subchunk1Size: UInt32 = 16
        let audioFormat: UInt16 = 1
        let sr32 = UInt32(sampleRate)
        withUnsafeBytes(of: subchunk1Size.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: audioFormat.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: numChannels.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sr32.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: byteRate.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: blockAlign.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: bitsPerSample.littleEndian) { data.append(contentsOf: $0) }
        data.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { data.append(contentsOf: $0) }

        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let pcm = Int16(clamped * 32767.0).littleEndian
            withUnsafeBytes(of: pcm) { data.append(contentsOf: $0) }
        }
        return data
    }
}
