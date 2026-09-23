import Foundation

/// A release version such as `0.3.0`, read from a bundle or a Git tag (`v0.3.0`).
///
/// `0.3` and `0.3.0` are the same version: missing components count as zero.
struct AppVersion: Comparable, Hashable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.first == "v" || text.first == "V" { text.removeFirst() }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    /// The version this copy of the app is.
    static var current: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap(AppVersion.init)
    }

    var description: String { components.map(String.init).joined(separator: ".") }

    /// Trailing zeros removed, so `0.3` and `0.3.0` compare and hash alike.
    private var normalized: [Int] {
        var result = components
        while result.count > 1, result.last == 0 { result.removeLast() }
        return result
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { lhs.normalized == rhs.normalized }

    func hash(into hasher: inout Hasher) { hasher.combine(normalized) }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
