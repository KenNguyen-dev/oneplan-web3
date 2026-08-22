//
//  BoardPinRow.swift
//  OnePlan
//
//  Created by Codex on 13/5/26.
//

import SwiftUI

struct BoardPinRow: View {
    enum SelectionStyle {
        case none
        case white
        case surface
    }

    private let title: String
    private let subtitle: String
    private let scheduleText: String?
    private let category: String?
    private let isVerified: Bool
    private let isSelected: Bool
    private let selectionStyle: SelectionStyle
    private let shadowOpacity: Double
    private let scale: Double
    private let horizontalOffset: CGFloat
    private let opacity: Double

    // showsDay: false when the hosting list already groups pins under day
    // dividers (ProcessPinView) — the tag then shows only the time mention.
    init(
        pin: ExtractedPinDto,
        position: Int,
        isSettled: Bool,
        isSelected: Bool,
        showsDay: Bool = true
    ) {
        self.title = pin.name
        self.subtitle = Self.subtitle(address: pin.address, notes: pin.notes)
        self.scheduleText = Self.scheduleText(
            dayNumber: showsDay ? pin.dayNumber : nil,
            timeOfDayText: pin.timeOfDayText
        )
        self.category = pin.category
        self.isVerified = pin.isVerified
        self.isSelected = isSelected
        self.selectionStyle = .white
        self.shadowOpacity = Self.pinShadowOpacity(
            for: position,
            isSettled: isSettled
        )
        self.scale = Self.pinScale(for: position, isSettled: isSettled)
        self.horizontalOffset = Self.pinHorizontalOffset(
            for: position,
            isSettled: isSettled
        )
        self.opacity = Self.pinOpacity(for: position, isSettled: isSettled)
    }

    init(pin: BoardPinDto, isSelected: Bool? = nil) {
        self.title = pin.name
        self.subtitle = Self.subtitle(address: pin.address, notes: pin.notes)
        self.scheduleText = Self.scheduleText(
            dayNumber: pin.dayNumber,
            timeOfDayText: pin.timeOfDayText
        )
        self.category = pin.category
        self.isVerified = pin.latitude != nil && pin.longitude != nil
        self.isSelected = isSelected ?? false
        self.selectionStyle = isSelected == nil ? .none : .surface
        self.shadowOpacity = 0
        self.scale = 1
        self.horizontalOffset = 0
        self.opacity = 1
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14.897, style: .continuous)
                    .fill(Constants.Neutral100)

                Image(poiImageName(for: category))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 14.897, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    if let scheduleText {
                        Text(scheduleText)
                            .font(Font.beVietnamPro(12, weight: .medium))
                            .tracking(-0.24)
                            .foregroundStyle(Constants.ContentB)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Constants.Neutral100, in: .capsule)
                    }

                    Text(title)
                        .font(.custom("Be Vietnam Pro", size: 17))
                        .tracking(-0.85)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)

                    if isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Constants.BlueBase)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut(duration: 0.25), value: isVerified)

                HStack(spacing: 3) {
                    Image("boardCompassIcon")
                        .resizable()
                        .renderingMode(.original)
                        .frame(width: 14, height: 14)
                        .accessibilityHidden(true)

                    Text(subtitle)
                        .font(.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentM)
                        .tracking(-0.28)
                        .lineLimit(1)
                }
                .animation(.easeInOut(duration: 0.25), value: subtitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if selectionStyle != .none {
                selectionIndicator
            }
        }
        .padding(12)
        .background(
            Constants.White,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(shadowOpacity), radius: 18, x: 0, y: 10)
        .scaleEffect(scale, anchor: .top)
        .offset(x: horizontalOffset, y: 0)
        .opacity(opacity)
        .accessibilityElement(children: .combine)
    }

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(indicatorFill)
                .overlay {
                    Circle()
                        .stroke(indicatorStroke, lineWidth: 1)
                }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: selectionStyle == .white ? 10 : 11, weight: .bold))
                    .foregroundStyle(Constants.White)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 20, height: 20)
    }

    private var indicatorFill: Color {
        if isSelected { return Constants.BlueBase }
        return selectionStyle == .surface ? Constants.Surface : Constants.White
    }

    private var indicatorStroke: Color {
        isSelected ? Constants.BlueBase : Constants.ContentL
    }

    // "Day 1 · 9am" fragment from the schedule the source video narrated.
    // Empty strings slip through `??` — an enriched pin whose placemark had
    // no formattable address stores "", which would render a blank row.
    private static func subtitle(address: String?, notes: String?) -> String {
        let trimmedAddress = address?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAddress, !trimmedAddress.isEmpty { return trimmedAddress }
        let trimmedNotes = notes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedNotes, !trimmedNotes.isEmpty { return trimmedNotes }
        return String(localized: "Location")
    }

    private static func scheduleText(
        dayNumber: Int?,
        timeOfDayText: String?
    ) -> String? {
        var parts: [String] = []
        if let dayNumber {
            parts.append(String(localized: "Day \(dayNumber)"))
        }
        if let timeOfDayText, !timeOfDayText.isEmpty {
            parts.append(timeOfDayText)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func pinOpacity(for position: Int, isSettled: Bool) -> Double {
        guard !isSettled else { return 1 }
        return max(0.34, 1 - (Double(position) * 0.28))
    }

    private static func pinScale(for position: Int, isSettled: Bool) -> Double {
        guard !isSettled else { return 1 }
        return max(0.84, 1 - (Double(position) * 0.05))
    }

    private static func pinHorizontalOffset(
        for position: Int,
        isSettled: Bool
    ) -> CGFloat {
        guard !isSettled else { return 0 }
        return CGFloat(min(position, 2)) * 18
    }

    private static func pinShadowOpacity(
        for position: Int,
        isSettled: Bool
    ) -> Double {
        guard !isSettled else { return 0 }
        return max(0.02, 0.08 - (Double(position) * 0.025))
    }
}
