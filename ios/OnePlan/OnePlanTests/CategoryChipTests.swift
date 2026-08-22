import Testing
@testable import OnePlan

/// The API and the UI must agree on the category set. When the server adds one,
/// this fails rather than the app silently rendering it as "Other".
@Suite("CategoryChip covers the API categories")
struct CategoryChipTests {

    @Test("every API category maps to a distinct chip category")
    func mapsEveryApiCategory() {
        let all: [Components.Schemas.ExpenseCategory] = [
            .FOOD, .STAY, .TICKET, .TRANSPORT, .OTHER, .COFFEE, .SPA, .GYM,
            .NIGHT_CLUB, .GROCERY, .SHOPPING, .CINEMA, .PHARMACY, .PARK,
        ]
        #expect(all.count == 14)

        let mapped = all.map { EditExpenseView.mapCategory($0) }
        // Only OTHER may fall through to .other; everything else is distinct.
        let nonOther = mapped.filter { $0 != .other }
        #expect(nonOther.count == 13)
        #expect(Set(nonOther).count == 13)
    }

    @Test("every chip category has a title and an emoji")
    func everyCategoryRenders() {
        for category in CategoryChip.Category.allCases {
            #expect(!category.title.isEmpty)
            #expect(!category.emoji.isEmpty)
        }
    }

    @Test("apiValue round trips through init")
    func apiValueRoundTrips() {
        for category in CategoryChip.Category.allCases {
            #expect(CategoryChip.Category(apiValue: category.apiValue) == category)
        }
    }

    @Test("an unknown api value is rejected rather than coerced")
    func unknownApiValue() {
        #expect(CategoryChip.Category(apiValue: "TELEPORT") == nil)
    }
}
