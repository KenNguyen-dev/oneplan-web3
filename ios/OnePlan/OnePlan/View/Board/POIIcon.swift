//
//  POIIcon.swift
//  OnePlan
//

import Foundation

// Maps Gemini's category enum to an asset in Assets.xcassets/poiIllustration.
// Unknown / "other" / nil fall back to a neutral pin illustration.
func poiImageName(for category: String?) -> String {
    switch category?.lowercased() {
    case "restaurant": return "restaurant"
    case "cafe": return "coffee"
    case "bar": return "night-club"
    case "hotel": return "hotel"
    case "shop": return "shopping"
    case "park", "beach", "viewpoint": return "park"
    case "museum", "landmark": return "museum"
    case "airport": return "airport"
    case "cinema": return "cinema"
    case "grocery": return "grocery"
    case "gym": return "gym"
    case "medical": return "medical"
    case "spa": return "spa"
    default: return "appLogoCutout"
    }
}
