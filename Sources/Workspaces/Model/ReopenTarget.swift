import CoreKit
import Foundation

/// What to open when a saved window has no match: a document, a folder or a web page, handed
/// to the window's own application. Nothing here runs Shell commands or AppleScript.
struct ReopenTarget: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case document, folder, webPage

        var id: String { rawValue }

        var label: String {
            switch self {
            case .document: return L10n.text("workspaces.document")
            case .folder: return L10n.text("workspaces.folder")
            case .webPage: return L10n.text("workspaces.web.page")
            }
        }
    }

    var kind: Kind
    /// As the user typed it: an absolute path, a file:// URL or an http(s) URL.
    var target: String

    /// The target for a window whose application reported `documentURL`. Titles are never
    /// read as paths.
    static func detected(documentURL: URL?) -> ReopenTarget? {
        guard let url = documentURL.flatMap({ normalizedURL($0.absoluteString) }) else { return nil }
        return url.isFileURL ? ReopenTarget(kind: .document, target: url.path)
            : ReopenTarget(kind: .webPage, target: url.absoluteString)
    }

    /// Accepts only absolute paths, local file URLs and http(s) URLs without credentials;
    /// relative paths and other schemes such as javascript: are refused.
    static func normalizedURL(_ value: String) -> URL? {
        guard !value.isEmpty, !containsControlCharacters(value) else { return nil }
        if value.hasPrefix("/") { return URL(fileURLWithPath: value).standardizedFileURL }
        guard let decoded = value.removingPercentEncoding, !containsControlCharacters(decoded),
              var components = URLComponents(string: value), let scheme = components.scheme?.lowercased() else {
            return nil
        }
        components.scheme = scheme
        if scheme == "file" {
            guard components.host == nil || components.host == "" || components.host == "localhost",
                  components.query == nil, components.fragment == nil,
                  components.percentEncodedPath.hasPrefix("/"), let url = components.url,
                  !url.path.isEmpty, !containsControlCharacters(url.path) else { return nil }
            return url.standardizedFileURL
        }
        guard ["http", "https"].contains(scheme), let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        components.host = host.lowercased()
        return components.url
    }

    var resourceURL: URL? { Self.normalizedURL(target) }

    /// Why the target cannot be opened with `bundleID`, or nil when it can.
    func validationError(bundleID: String?) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard let bundleID, bundleID.contains("."), bundleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return L10n.text("workspaces.this.app.has.no.valid.identifier.and")
        }
        guard let url = resourceURL else { return L10n.text("workspaces.enter.an.absolute.path.a.file.url") }
        switch kind {
        case .webPage: return url.isFileURL ? L10n.text("workspaces.web.urls.must.begin.with.http.or") : nil
        case .document, .folder: return url.isFileURL ? nil : L10n.text("workspaces.documents.and.folders.require.an.absolute.path")
        }
    }

    private static func containsControlCharacters(_ text: String) -> Bool {
        text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
