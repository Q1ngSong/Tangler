/// Which applications a scan reads.
enum ScanScope: Equatable {
    case all
    case applications(Set<Int32>)

    func merged(with other: ScanScope) -> ScanScope {
        switch (self, other) {
        case (.applications(let mine), .applications(let theirs)): return .applications(mine.union(theirs))
        case (.all, _), (_, .all): return .all
        }
    }
}
