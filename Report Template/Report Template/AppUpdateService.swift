import Foundation
import AppKit

@MainActor
final class AppUpdateService: ObservableObject {
    struct ReleaseInfo {
        let version: String
        let releaseURL: URL
        let downloadURL: URL
    }
    
    enum State {
        case idle
        case checking
        case upToDate
        case updateAvailable(ReleaseInfo)
        case failed(String)
    }
    
    @Published private(set) var state: State = .idle
    
    var isChecking: Bool {
        if case .checking = state {
            return true
        }
        return false
    }
    
    var availableVersion: String? {
        guard case let .updateAvailable(release) = state else {
            return nil
        }
        return release.version
    }
    
    private let owner: String
    private let repo: String
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init(owner: String, repo: String, session: URLSession = .shared) {
        self.owner = owner
        self.repo = repo
        self.session = session
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }
    
    @discardableResult
    func checkForUpdates() async -> State {
        if isChecking {
            return state
        }
        
        state = .checking
        
        do {
            let latestRelease = try await fetchLatestRelease()
            let latestVersion = normalizedVersion(latestRelease.tagName)
            let currentVersion = normalizedVersion(currentAppVersion)
            
            if isNewerVersion(latestVersion, than: currentVersion) {
                let downloadURL = latestRelease.preferredDownloadURL ?? latestRelease.htmlURL
                state = .updateAvailable(
                    ReleaseInfo(
                        version: latestVersion,
                        releaseURL: latestRelease.htmlURL,
                        downloadURL: downloadURL
                    )
                )
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? "Unable to check for updates right now.")
        }
        
        return state
    }
    
    func openAvailableUpdate() {
        guard case let .updateAvailable(release) = state else {
            return
        }
        
        NSWorkspace.shared.open(release.downloadURL)
    }
    
    private var currentAppVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return shortVersion ?? buildVersion ?? "0"
    }
    
    private func fetchLatestRelease() async throws -> GitHubRelease {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw UpdateServiceError.invalidRepository
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("PMGReportUpdater", forHTTPHeaderField: "User-Agent")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UpdateServiceError.httpStatus(httpResponse.statusCode)
        }
        
        do {
            return try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateServiceError.invalidReleasePayload
        }
    }
    
    private func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
    
    private func isNewerVersion(_ remoteVersion: String, than localVersion: String) -> Bool {
        let remote = versionComponents(from: remoteVersion)
        let local = versionComponents(from: localVersion)
        
        if remote.isEmpty || local.isEmpty {
            return remoteVersion.compare(localVersion, options: [.numeric, .caseInsensitive]) == .orderedDescending
        }
        
        let count = max(remote.count, local.count)
        for index in 0..<count {
            let remotePart = index < remote.count ? remote[index] : 0
            let localPart = index < local.count ? local[index] : 0
            
            if remotePart != localPart {
                return remotePart > localPart
            }
        }
        
        return false
    }
    
    private func versionComponents(from version: String) -> [Int] {
        version
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }
    }
}

private enum UpdateServiceError: LocalizedError {
    case invalidRepository
    case invalidResponse
    case invalidReleasePayload
    case httpStatus(Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "GitHub repository is not configured correctly."
        case .invalidResponse:
            return "Received an invalid response from GitHub."
        case .invalidReleasePayload:
            return "Latest GitHub release payload could not be parsed."
        case let .httpStatus(statusCode):
            if statusCode == 404 {
                return "No GitHub release found yet. Publish a release first."
            }
            if statusCode == 403 {
                return "GitHub API rate limit reached. Try again later."
            }
            return "GitHub update check failed with status code \(statusCode)."
        }
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [GitHubAsset]
    
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }
    
    var preferredDownloadURL: URL? {
        if let installerCommand = assets.first(where: { $0.name.lowercased().hasSuffix("-installer.command") }) {
            return installerCommand.browserDownloadURL
        }
        if let installer = assets.first(where: { $0.name.lowercased().hasSuffix("-installer.sh") }) {
            return installer.browserDownloadURL
        }
        if let dmg = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmg.browserDownloadURL
        }
        if let pkg = assets.first(where: { $0.name.lowercased().hasSuffix(".pkg") }) {
            return pkg.browserDownloadURL
        }
        if let zip = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) {
            return zip.browserDownloadURL
        }
        return assets.first?.browserDownloadURL
    }
}

private struct GitHubAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    
    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
