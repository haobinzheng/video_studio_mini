import Foundation

/// Script paragraphs for Edit Story and paragraph-aligned narration: split on blank lines (`\n\n` or more).
/// Chunks that are empty or whitespace-only are dropped (extra newlines do not create paragraphs).
enum StoryScriptPartition {
    static func nonEmptyParagraphs(from text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
