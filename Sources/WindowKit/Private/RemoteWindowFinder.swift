import ApplicationServices
import Contracts
import Foundation

/// Finds windows Accessibility does not list, such as those on other Spaces, by building
/// elements from remote tokens (the technique AltTab uses). Each candidate costs a round
/// trip, so it only looks for window numbers nobody knows yet, within a time budget, and
/// stops asking about numbers that did not turn up in a few scans.
final class RemoteWindowFinder: @unchecked Sendable {
    private typealias CreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    /// The token layout is the process, a zero, this marker ("coco") and the element number.
    private static let marker: Int32 = 0x636f_636f
    private static let elementLimit: UInt64 = 1000
    private static let budget: TimeInterval = 0.1
    private static let attemptLimit = 3

    private let create: CreateWithRemoteToken
    private let identity: WindowIdentity
    private let lock = NSLock()
    private var attempts: [Int32: [WindowID: Int]] = [:]

    init?(identity: WindowIdentity) {
        guard let create = PrivateSymbols.function(.elementWithRemoteToken, as: CreateWithRemoteToken.self) else { return nil }
        self.create = create
        self.identity = identity
    }

    /// Harmless probe: building an element for this process makes no call into any app.
    static func canBuildElements() -> Bool {
        guard let create = PrivateSymbols.function(.elementWithRemoteToken, as: CreateWithRemoteToken.self) else { return false }
        return create(token(pid: getpid(), elementID: 0) as CFData)?.takeRetainedValue() != nil
    }

    func windows(of pid: Int32, missing: Set<WindowID>) -> [AXUIElement] {
        var wanted = locked { missing.filter { (attempts[pid]?[$0] ?? 0) < Self.attemptLimit } }
        guard !wanted.isEmpty else { return [] }
        var found: [AXUIElement] = []
        var token = Self.token(pid: pid, elementID: 0)
        let deadline = Date().addingTimeInterval(Self.budget)
        var elementID: UInt64 = 0
        while elementID < Self.elementLimit, !wanted.isEmpty, Date() < deadline {
            Self.write(elementID, into: &token)
            elementID += 1
            guard let element = create(token as CFData)?.takeRetainedValue() else { continue }
            AXUIElementSetMessagingTimeout(element, AXRead.timeout)
            let subrole = AXRead.string(AXRead.attribute(element, kAXSubroleAttribute))
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole,
                  let id = identity.windowID(of: element), wanted.remove(id) != nil else { continue }
            found.append(element)
        }
        locked { for id in wanted { attempts[pid, default: [:]][id, default: 0] += 1 } }
        return found
    }

    func forget(pid: Int32) {
        locked { attempts[pid] = nil }
    }

    private static func token(pid: Int32, elementID: UInt64) -> Data {
        var data = Data(count: 20)
        withUnsafeBytes(of: pid) { data.replaceSubrange(0..<4, with: $0) }
        withUnsafeBytes(of: Int32(0)) { data.replaceSubrange(4..<8, with: $0) }
        withUnsafeBytes(of: marker) { data.replaceSubrange(8..<12, with: $0) }
        write(elementID, into: &data)
        return data
    }

    private static func write(_ elementID: UInt64, into data: inout Data) {
        withUnsafeBytes(of: elementID) { data.replaceSubrange(12..<20, with: $0) }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
