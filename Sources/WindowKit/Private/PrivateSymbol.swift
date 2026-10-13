import Darwin

/// Every private function WindowKit may call. Each one is probed at launch (design section 5.2)
/// and has a public fallback, except `dockNotification`: without it desktops simply cannot be
/// added or removed. Nothing outside `Private/` names them.
enum PrivateSymbol: String, CaseIterable {
    case windowForElement = "_AXUIElementGetWindow"
    case elementWithRemoteToken = "_AXUIElementCreateWithRemoteToken"
    case mainConnection = "SLSMainConnectionID"
    case managedDisplaySpaces = "SLSCopyManagedDisplaySpaces"
    case spacesForWindows = "SLSCopySpacesForWindows"
    case setFrontProcess = "_SLPSSetFrontProcessWithOptions"
    case postEventRecord = "SLPSPostEventRecordTo"
    /// Public but deprecated; resolved at runtime so a future SDK cannot break the build.
    case processForPID = "GetProcessForPID"
    /// Opens and closes Mission Control, as the Mission Control key does.
    case dockNotification = "CoreDockSendNotification"

    var isSkyLight: Bool {
        switch self {
        case .mainConnection, .managedDisplaySpaces, .spacesForWindows, .setFrontProcess, .postEventRecord: return true
        case .windowForElement, .elementWithRemoteToken, .processForPID, .dockNotification: return false
        }
    }
}

/// Resolves private symbols: SkyLight's from the framework, the rest from loaded images.
enum PrivateSymbols {
    static let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    private static let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)

    static func address(of symbol: PrivateSymbol) -> UnsafeMutableRawPointer? {
        let handle = symbol.isSkyLight ? skyLight : defaultHandle
        guard let handle else { return nil }
        return dlsym(handle, symbol.rawValue)
    }

    /// The symbol as a C function of type `T`, or nil when it is missing.
    static func function<T>(_ symbol: PrivateSymbol, as type: T.Type) -> T? {
        address(of: symbol).map { unsafeBitCast($0, to: type) }
    }
}
