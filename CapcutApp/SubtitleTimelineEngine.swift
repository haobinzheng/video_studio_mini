import Foundation

struct SubtitleTimelineEngine {
    /// Matches `VideoExporter.captionLagCompensation`: show captions slightly early so on-screen text lines up with heard speech after encode/render latency.
    static let displayLeadSeconds: TimeInterval = 0.3

    typealias Cue = NarrationPreviewBuilder.SubtitleCue

    let cues: [Cue]

    init(cues: [Cue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    func cue(at time: TimeInterval) -> Cue? {
        guard !cues.isEmpty else { return nil }

        var lastStarted: Int?
        for i in cues.indices where cues[i].start <= time {
            lastStarted = i
        }

        guard let idx = lastStarted else {
            return cues.first
        }

        let active = cues[idx]
        if time <= active.end {
            return active
        }

        if idx + 1 < cues.count, time < cues[idx + 1].start {
            return active
        }

        if idx == cues.indices.last {
            return active
        }

        return cues[idx + 1]
    }

    static func load(from url: URL) throws -> SubtitleTimelineEngine {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let cues = try decoder.decode([Cue].self, from: data)
        return SubtitleTimelineEngine(cues: cues)
    }

    static func save(_ cues: [Cue], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cues)
        try data.write(to: url, options: .atomic)
    }
}
