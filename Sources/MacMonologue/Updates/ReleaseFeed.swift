import Foundation

/// One published version, as the GitHub REST API describes it.
struct Release: Decodable, Equatable, Identifiable, Sendable {
    struct Asset: Decodable, Equatable, Sendable {
        let name: String
        let size: Int
        let downloadURL: URL
        /// `sha256:<hex>`, computed by GitHub itself (exposed since 2025-06).
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case downloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let isDraft: Bool
    let isPrerelease: Bool
    let publishedAt: Date?
    let pageURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, assets
        case tagName = "tag_name"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case publishedAt = "published_at"
        case pageURL = "html_url"
    }

    var id: String { tagName }
    var version: AppVersion? { AppVersion(tagName) }

    /// The app itself, under the name that stays the same in every release.
    var appAsset: Asset? { assets.first { $0.name == ReleaseFeed.assetName } }

    /// The expected SHA-256 of the app asset, lowercase hex, if GitHub gave one.
    var appAssetSHA256: String? {
        guard let digest = appAsset?.digest, digest.hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst("sha256:".count)).lowercased()
    }
}

/// Where new versions are announced: the repository's GitHub releases.
enum ReleaseFeed {
    static let repository = "alexanderpuschkinberlin/Mac-Monologue"
    /// The same in every release, which is what makes
    /// `…/releases/latest/download/Mac-Monologue.zip` a permanent download link.
    static let assetName = "Mac-Monologue.zip"

    static let pageURL = URL(string: "https://github.com/\(repository)/releases")!
    static let latestDownloadURL = URL(string: "https://github.com/\(repository)/releases/latest/download/\(assetName)")!
    private static let apiURL = URL(string: "https://api.github.com/repos/\(repository)/releases?per_page=30")!

    /// Overridable with `-UpdateFeedURL <url>` for testing against a local feed.
    /// Harmless if misused: whatever it points at, an update is only installed if
    /// it is signed with the same certificate as the running app.
    static var feedURL: URL {
        UserDefaults.standard.string(forKey: "UpdateFeedURL").flatMap(URL.init(string:)) ?? apiURL
    }

    static func decode(_ data: Data) throws -> [Release] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Release].self, from: data)
    }

    /// The releases worth offering: published, carrying the app, and newer than
    /// what is installed — newest first. Everything from the installed version up
    /// is kept, so the changelog covers every version being skipped over.
    static func updates(in releases: [Release], newerThan installed: AppVersion) -> [Release] {
        releases
            .filter { !$0.isDraft && !$0.isPrerelease && $0.appAsset != nil }
            .filter { ($0.version ?? installed) > installed }
            .sorted { ($0.version ?? installed) > ($1.version ?? installed) }
    }

    static func fetch() async throws -> [Release] {
        var request = URLRequest(url: feedURL, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub rejects API requests without one.
        request.setValue("Mac-Monologue/\(AppVersion.current?.description ?? "0")", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.status(http.statusCode)
        }
        return try decode(data)
    }

    enum FeedError: LocalizedError {
        case status(Int)

        var errorDescription: String? {
            switch self {
            case .status(403), .status(429):
                "GitHub is limiting requests right now. Try again in an hour."
            case .status(let code):
                "GitHub answered with an error (\(code))."
            }
        }
    }
}
