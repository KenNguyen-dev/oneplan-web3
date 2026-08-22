import SwiftUI

enum LocationDetailTab: String, CaseIterable, Identifiable {
    case top = "Top"
    case photo = "Photo"

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .top: String(localized: "Top", comment: "Location detail tab")
        case .photo: String(localized: "Photo", comment: "Location detail tab")
        }
    }
}

enum LocationDetailSheetMode {
    case minimized      // Map focused, sheet peek (title + stats only)
    case medium         // Half sheet (title, description, buttons, start of list)
    case expanded       // Full sheet (scrollable content)
}

struct LocationDetailScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct LocationDetailContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct LocationTopEntry: Identifiable {
    let id: String
    let name: String
    let mutualFriendsText: String
    let ranking: String
    let isFriend: Bool
}

/// Picker-mode configuration for `LocationDetailView`. When present, the view
/// hosts the search/board picker as a native morphing sheet over the map and
/// reports the user's choice through these closures (Apple-Maps style). When
/// `nil`, the view behaves as the read-only standalone map detail.
struct LocationPickerConfig {
    var tripId: Int? = nil
    /// Day-number to attach bulk-created plan items to (planning-mode trips).
    /// Mutually exclusive with `planDate`.
    var dayNumber: Int? = nil
    /// Plan-date (yyyy-MM-dd) to attach bulk-created plan items to (ongoing trips).
    /// Mutually exclusive with `dayNumber`.
    var planDate: String? = nil
    var onLocationSelected: (ChooseLocationItem) -> Void = { _ in }
    var onPinsAddedToTrip: () -> Void = {}
    /// When set, selecting board pins returns them to the caller (e.g. to append
    /// to an in-memory draft) instead of writing them to a trip via the API.
    /// Its presence also reveals the "My Board" tab even when `tripId` is nil.
    var onBoardPinsSelected: (([BoardPinDto]) -> Void)? = nil
}

/// Which surface the picker-mode native sheet is currently showing.
enum LocationSheetContent: Equatable {
    case search    // ChooseLocationPickerContent (search + My Board)
    case detail    // place detail (summary, header, Add to plan)
}
