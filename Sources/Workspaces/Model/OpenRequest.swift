import Foundation

/// An application to launch, optionally with documents, folders or web pages to open in it.
struct OpenRequest: Hashable, Sendable {
    var bundleID: String
    var urls: [URL] = []
}
