import Foundation

struct SubtitleTimelineEngine {
    typealias Cue = NarrationPreviewBuilder.SubtitleCue

    let cues: [Cue]

    init(cues: [Cue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    func index(at time: TimeInterval) -> Int? {
        guard !cues.isEmpty else { return nil }

        var low = 0
        var high = cues.count - 1

        while low <= high {
            let mid = (low + high) / 2
            let cue = cues[mid]

            if time < cue.start {
                high = mid - 1
            } else if time > cue.end {
                low = mid + 1
            } else {
                return mid
            }
        }

        if let first = cues.first, time < first.start {
            return 0
        }

        if let lastIndex = cues.indices.last, time >= cues[lastIndex].end {
            return lastIndex
        }

        return min(max(low, 0), cues.count - 1)
    }

    func cue(at time: TimeInterval) -> Cue? {
        guard let index = index(at: time), cues.indices.contains(index) else { return nil }
        return cues[index]
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
