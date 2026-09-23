import Foundation

/// A release's notes, as headings and bullet points the update window can show.
struct ChangelogSection: Equatable, Identifiable, Sendable {
    enum Item: Equatable, Sendable {
        case bullet(String)
        case paragraph(String)
    }

    let version: String
    let date: Date?
    let items: [Item]

    var id: String { version }
}

/// Turns release notes into sections, line by line.
///
/// Not handed to SwiftUI as Markdown: `Text` renders inline Markdown only, and
/// flattens lists into one run-on line. The notes come from our own
/// `CHANGELOG.md`, so a small, predictable reading of them is enough.
enum ChangelogFormatter {
    static func sections(for releases: [Release]) -> [ChangelogSection] {
        releases.map { release in
            ChangelogSection(
                version: release.version?.description ?? release.tagName,
                date: release.publishedAt,
                items: items(in: release.body ?? "")
            )
        }
    }

    static func items(in body: String) -> [ChangelogSection.Item] {
        var items: [ChangelogSection.Item] = []
        var paragraph: [String] = []

        func closeParagraph() {
            if !paragraph.isEmpty { items.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        // GitHub stores release notes with Windows line endings.
        for rawLine in body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n",
                                                                                omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                closeParagraph()
            } else if line.hasPrefix("#") {
                // The version heading is shown from the release itself.
                closeParagraph()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                closeParagraph()
                items.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
            } else if case .bullet(let previous)? = items.last, paragraph.isEmpty,
                      rawLine.hasPrefix("  ") {
                // A bullet wrapped onto an indented next line.
                items[items.count - 1] = .bullet(previous + " " + line)
            } else {
                paragraph.append(line)
            }
        }
        closeParagraph()
        return items
    }
}
