//
//  CategoryChip.swift
//  OnePlan
//
//  Created by ken on 25/2/26.
//

import SwiftUI
import MapKit

struct CategoryChip: View {
    /// Mirrors `Components.Schemas.ExpenseCategory` one for one.
    ///
    /// `CategoryChipTests` fails if the server grows a category this does not
    /// cover, so a new value can never silently render as "Other".
    ///
    /// Three sets of artwork coexist here, for different callers. `lightIconName`
    /// and `darkIconName` are the original chip bitmaps, which only the first
    /// five cases have. `iconAsset` is the illustration the vault design ships,
    /// which twelve have. `emoji` is the fallback for whatever neither covers.
    enum Category: CaseIterable {
        case food
        case stay
        case ticket
        case transport
        case other
        case coffee
        case spa
        case gym
        case nightClub
        case grocery
        case shopping
        case cinema
        case pharmacy
        case park

        var title: String {
            switch self {
            case .food:
                return String(localized: "Food", comment: "Expense category")
            case .stay:
                return String(localized: "Stay", comment: "Expense category")
            case .ticket:
                return String(localized: "Ticket", comment: "Expense category")
            case .transport:
                return String(localized: "Transport", comment: "Expense category")
            case .other:
                return String(localized: "Other", comment: "Expense category")
            case .coffee:
                return String(localized: "Coffee", comment: "Expense category")
            case .spa:
                return String(localized: "Spa / Healing", comment: "Expense category")
            case .gym:
                return String(localized: "Gym", comment: "Expense category")
            case .nightClub:
                return String(localized: "Night club", comment: "Expense category")
            case .grocery:
                return String(localized: "Grocery", comment: "Expense category")
            case .shopping:
                return String(localized: "Shopping / Mall", comment: "Expense category")
            case .cinema:
                return String(localized: "Cinema", comment: "Expense category")
            case .pharmacy:
                return String(localized: "Pharmacy", comment: "Expense category")
            case .park:
                return String(localized: "Park", comment: "Expense category")
            }
        }

        /// The illustrated icon the design ships for this category.
        ///
        /// Empty for the two the mockup does not define: its last rows fall
        /// outside the sheet, so Figma renders one clipped and one blank. Those
        /// fall back to the emoji below until the design supplies them.
        var iconAsset: String {
            switch self {
            case .food: return "catFood"
            case .stay: return "catStay"
            case .ticket: return "catTicket"
            case .transport: return "catTransport"
            case .coffee: return "catCoffee"
            case .spa: return "catSpa"
            case .gym: return "catGym"
            case .nightClub: return "catNightClub"
            case .grocery: return "catGrocery"
            case .shopping: return "catShopping"
            case .cinema: return "catCinema"
            case .pharmacy: return "catPharmacy"
            case .park, .other: return ""
            }
        }

        /// The fallback for a category with no illustration yet.
        var emoji: String {
            switch self {
            case .food: return "🍽️"
            case .stay: return "🏨"
            case .ticket: return "🎫"
            case .transport: return "✈️"
            case .other: return "🧾"
            case .coffee: return "🧋"
            case .spa: return "💆"
            case .gym: return "🏋️"
            case .nightClub: return "🪩"
            case .grocery: return "🛍️"
            case .shopping: return "🧺"
            case .cinema: return "🍿"
            case .pharmacy: return "💊"
            case .park: return "🌵"
            }
        }

        var selectedBackgroundColor: Color {
            switch self {
            case .food:
                return Constants.Warning500
            case .stay:
                return Constants.Green500
            case .ticket:
                return Constants.BlueBase
            case .transport:
                return Constants.Purple500
            case .other:
                return Constants.Neutral600
            case .coffee, .grocery, .shopping:
                return Constants.Warning500
            case .spa, .park:
                return Constants.Green500
            case .gym, .pharmacy:
                return Constants.Secondary
            case .nightClub, .cinema:
                return Constants.Purple500
            }
        }

        /// Empty when the case has no bitmap icon; `CategoryChip` then draws the
        /// emoji instead.
        var darkIconName: String {
            switch self {
            case .food:
                return "darkFoodIcon"
            case .stay:
                return "darkBuildingIcon"
            case .ticket:
                return "darkTicketIcon"
            case .transport:
                return "darkPlaneIcon"
            case .other, .coffee, .spa, .gym, .nightClub, .grocery, .shopping,
                 .cinema, .pharmacy, .park:
                return ""
            }
        }

        var apiValue: String {
            switch self {
            case .food: return "FOOD"
            case .stay: return "STAY"
            case .ticket: return "TICKET"
            case .transport: return "TRANSPORT"
            case .other: return "OTHER"
            case .coffee: return "COFFEE"
            case .spa: return "SPA"
            case .gym: return "GYM"
            case .nightClub: return "NIGHT_CLUB"
            case .grocery: return "GROCERY"
            case .shopping: return "SHOPPING"
            case .cinema: return "CINEMA"
            case .pharmacy: return "PHARMACY"
            case .park: return "PARK"
            }
        }

        static func from(poiCategory: MKPointOfInterestCategory?) -> Category? {
            guard let poi = poiCategory else { return nil }
            switch poi {
            case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket:
                return .food
            case .hotel, .campground:
                return .stay
            case .museum, .movieTheater, .theater, .amusementPark, .aquarium, .zoo, .stadium, .nightlife:
                return .ticket
            case .airport, .publicTransport, .carRental, .evCharger, .gasStation, .parking:
                return .transport
            default:
                return nil
            }
        }

        init?(apiValue: String) {
            // Derived from `apiValue` so the two can never drift apart.
            guard let match = Category.allCases.first(where: { $0.apiValue == apiValue })
            else { return nil }
            self = match
        }

        var lightIconName: String {
            switch self {
            case .food:
                return "lightFoodIcon"
            case .stay:
                return "lightBuildingIcon"
            case .ticket:
                return "lightTicketIcon"
            case .transport:
                return "lightPlaneIcon"
            case .other, .coffee, .spa, .gym, .nightClub, .grocery, .shopping,
                 .cinema, .pharmacy, .park:
                return ""
            }
        }
    }

    let category: Category
    let isSelected: Bool

    @State private var isPressed = false

    private var backgroundColor: Color {
        isSelected ? category.selectedBackgroundColor : Constants.Surface
    }

    private var contentColor: Color {
        isSelected ? Constants.White : Constants.ContentB
    }

    private var iconName: String {
        isSelected ? category.lightIconName : category.darkIconName
    }

    @ViewBuilder
    private var icon: some View {
        if iconName.isEmpty {
            // No bitmap for this category. `.other` keeps its original glyph;
            // the vault categories fall back to the emoji the design uses.
            if category == .other {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(contentColor)
                    .frame(width: 16, height: 16)
            } else {
                Text(category.emoji)
                    .font(.system(size: 12))
                    .frame(width: 16, height: 16)
            }
        } else {
            Image(iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            icon

            Text(category.title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(contentColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .cornerRadius(21)
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            isPressed = pressing
            if pressing {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }, perform: {})
    }
}

#Preview {
    VStack(spacing: 12) {
        CategoryChip(category: .food, isSelected: true)
        CategoryChip(category: .stay, isSelected: true)
        CategoryChip(category: .ticket, isSelected: false)
        CategoryChip(category: .transport, isSelected: false)
        CategoryChip(category: .other, isSelected: true)
    }
    .padding()
    .background(Constants.OnSurface)
}
