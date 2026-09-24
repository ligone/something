import Observation

/// Which exhibit is on screen. Shared by the window, the menu commands and the
/// screenshot tour, so it lives in one place.
@Observable
final class Navigation {
    static let shared = Navigation()

    var selection: Exhibit? = .welcome

    var current: Exhibit { selection ?? .welcome }

    func show(_ exhibit: Exhibit) {
        selection = exhibit
    }

    func showNext() {
        selection = current.next
    }

    func showPrevious() {
        selection = current.previous
    }
}
