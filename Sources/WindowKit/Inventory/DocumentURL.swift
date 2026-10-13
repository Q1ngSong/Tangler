import Foundation

/// Filters the `AXDocument` attribute down to what a workspace may reopen: absolute local
/// files and web pages. Custom schemes could launch arbitrary actions, so the user must
/// configure those explicitly instead.
enum DocumentURL {
    static func accept(_ value: Any?) -> URL? {
        let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        guard let url, let scheme = url.scheme?.lowercased() else { return nil }
        if scheme == "file" {
            guard url.path.hasPrefix("/"), url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
            return url.standardizedFileURL
        }
        guard ["https", "http"].contains(scheme), let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
