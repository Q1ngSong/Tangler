import Contracts
import CoreGraphics

/// Pairs an Accessibility window with its window server number by previous identity,
/// geometry and title, for when the exact private lookup is unavailable (design section 5.2).
/// Ambiguous matches return nil: controlling the wrong window is worse than skipping one.
enum WindowMatcher {
    struct Candidate: Equatable {
        var id: WindowID
        var frame: CGRect
        var title: String
    }

    static func match(frame: CGRect, title: String, among candidates: [Candidate], previousID: WindowID?) -> WindowID? {
        if let previousID, candidates.contains(where: { $0.id == previousID }) { return previousID }
        let ranked = candidates
            .map { (id: $0.id, score: score(frame: frame, title: title, candidate: $0)) }
            .filter { $0.score > 40 }
            .sorted { $0.score > $1.score }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1 && best.score - ranked[1].score < 8 { return nil }
        return best.id
    }

    static func score(frame: CGRect, title: String, candidate: Candidate) -> Double {
        let distance = Double(abs(candidate.frame.minX - frame.minX) + abs(candidate.frame.minY - frame.minY)
            + abs(candidate.frame.width - frame.width) + abs(candidate.frame.height - frame.height))
        let titleMatches = !title.isEmpty && candidate.title == title
        if distance <= 8 { return 100 - distance + (titleMatches ? 40 : 0) }
        // A title alone is not enough: duplicate documents and stale snapshots share titles.
        return titleMatches && distance <= 80 ? 70 - distance / 4 : 0
    }
}
