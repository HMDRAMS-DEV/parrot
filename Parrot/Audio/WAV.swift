import AVFoundation

/// Saves and loads 16 kHz mono clips. Files are 16-bit PCM, half the size of Float.
enum WAV {
    static func write(_ samples: [Float], to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Recorder.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData?[0].update(from: source.baseAddress!, count: samples.count)
        }
        try file.write(from: buffer)
    }

    /// Reads any audio file and returns 16 kHz mono samples.
    static func read(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Recorder.sampleRate, channels: 1, interleaved: false),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: input)
        if file.processingFormat == output {
            return Array(UnsafeBufferPointer(start: input.floatChannelData?[0], count: Int(input.frameLength)))
        }
        guard let converter = AVAudioConverter(from: file.processingFormat, to: output),
              let converted = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: AVAudioFrameCount(Double(input.frameLength) * output.sampleRate / file.processingFormat.sampleRate) + 1)
        else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: converted.floatChannelData?[0], count: Int(converted.frameLength)))
    }
}
