//
//  Calendar.swift
//  OnePlan
//
//  Created by ken on 3/5/26.
//

import SwiftUI

struct MultiSelectCalendar: View {
    private let month: Date
    private let currentDate: Date?
    private let selectedRange: ClosedRange<Date>?
    private let disabledBefore: Date?
    private let timeZone: TimeZone
    private let onSelectDate: (Date) -> Void

    private var gregorianCalendar: Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    private var monthTitle: String {
        monthFormatter.string(from: monthStart)
    }

    private var yearTitle: String {
        yearFormatter.string(from: monthStart)
    }

    private var monthStart: Date {
        let components = gregorianCalendar.dateComponents([.year, .month], from: month)
        return gregorianCalendar.date(from: components) ?? month
    }

    private var monthGridDays: [CalendarDay] {
        guard
            let daysRange = gregorianCalendar.range(of: .day, in: .month, for: monthStart),
            let firstWeekday = gregorianCalendar.dateComponents([.weekday], from: monthStart).weekday
        else {
            return []
        }

        let leadingEmptyDays = firstWeekday - gregorianCalendar.firstWeekday
        let monthDays = daysRange.compactMap { day -> CalendarDay? in
            guard
                let date = gregorianCalendar.date(
                    byAdding: .day,
                    value: day - 1,
                    to: monthStart
                )
            else {
                return nil
            }

            return CalendarDay(id: "day-\(day)", date: date, dayNumber: day)
        }

        let totalCells = ((leadingEmptyDays + monthDays.count + 6) / 7) * 7
        let trailingEmptyDays = max(0, totalCells - leadingEmptyDays - monthDays.count)
        let leadingDays = (0..<leadingEmptyDays).map { index in
            CalendarDay(id: "leading-\(index)", date: nil, dayNumber: 0)
        }
        let trailingDays = (0..<trailingEmptyDays).map { index in
            CalendarDay(id: "trailing-\(index)", date: nil, dayNumber: 0)
        }

        return leadingDays + monthDays + trailingDays
    }

    private var weeks: [[CalendarDay]] {
        stride(from: 0, to: monthGridDays.count, by: 7).map { startIndex in
            Array(monthGridDays[startIndex..<min(startIndex + 7, monthGridDays.count)])
        }
    }

    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar
        formatter.timeZone = timeZone
        // DISPLAY: month name follows the current locale (Vietnamese months).
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter
    }

    private var yearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter
    }

    init(
        month: Date = Date(),
        currentDate: Date? = Date(),
        selectedRange: ClosedRange<Date>? = nil,
        disabledBefore: Date? = Date(),
        timeZone: TimeZone = .current,
        onSelectDate: @escaping (Date) -> Void = { _ in }
    ) {
        self.month = month
        self.currentDate = currentDate
        self.selectedRange = selectedRange
        self.disabledBefore = disabledBefore
        self.timeZone = timeZone
        self.onSelectDate = onSelectDate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerRow
            weekdayRow

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week) { day in
                        dayCell(day)
                    }
                }
                .frame(height: 48)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .top)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var headerRow: some View {
        HStack {
            Text(monthTitle)
                .calendarHeaderText()
                .frame(width: 112, height: 48, alignment: .leading)
                .padding(.leading, 20)

            Spacer(minLength: 0)

            Text(yearTitle)
                .calendarHeaderText()
                .frame(width: 88, height: 48, alignment: .trailing)
                .padding(.trailing, 20)
        }
        .frame(height: 48)
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(CalendarStyle.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(CalendarStyle.headerFont)
                    .foregroundStyle(index == 0 || index == 6 ? CalendarStyle.primary : CalendarStyle.neutral)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 48)
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        Group {
            if let date = day.date {
                Button {
                    onSelectDate(date)
                } label: {
                    Text("\(day.dayNumber)")
                        .font(CalendarStyle.dayFont)
                        .foregroundStyle(textColor(for: date))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(backgroundShape(for: date))
                }
                .buttonStyle(.plain)
                .disabled(isDisabled(date))
                .accessibilityLabel(accessibilityLabel(for: date))
                .accessibilityAddTraits(accessibilityTraits(for: date))
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func backgroundShape(for date: Date) -> some View {
        if let rangePosition = selectedRangePosition(for: date) {
            CalendarRangeBackground(position: rangePosition)
                .fill(CalendarStyle.primary)
        } else if isCurrentDate(date) {
            Circle()
                .fill(CalendarStyle.secondary)
                .padding(.vertical, -2)
                .padding(.horizontal, 3)
        }
    }

    private func textColor(for date: Date) -> Color {
        if isInSelectedRange(date) || isCurrentDate(date) {
            return CalendarStyle.invertedText
        }

        if isDisabled(date) {
            return CalendarStyle.disabled
        }

        if isWeekend(date) {
            return CalendarStyle.secondary
        }

        return CalendarStyle.primaryText
    }

    private func accessibilityLabel(for date: Date) -> Text {
        let formatter = DateFormatter()
        formatter.calendar = gregorianCalendar
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .full
        return Text(formatter.string(from: date))
    }

    private func accessibilityTraits(for date: Date) -> AccessibilityTraits {
        isInSelectedRange(date) ? [.isButton, .isSelected] : .isButton
    }

    private func isCurrentDate(_ date: Date) -> Bool {
        guard let currentDate else { return false }
        return gregorianCalendar.isDate(date, inSameDayAs: currentDate)
    }

    private func isDisabled(_ date: Date) -> Bool {
        guard let disabledBefore else { return false }
        return gregorianCalendar.compare(date, to: disabledBefore, toGranularity: .day) == .orderedAscending
    }

    private func isWeekend(_ date: Date) -> Bool {
        let weekday = gregorianCalendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    private func isInSelectedRange(_ date: Date) -> Bool {
        selectedRangePosition(for: date) != nil
    }

    private func selectedRangePosition(for date: Date) -> CalendarRangePosition? {
        guard
            let selectedRange,
            gregorianCalendar.compare(date, to: selectedRange.lowerBound, toGranularity: .day) != .orderedAscending,
            gregorianCalendar.compare(date, to: selectedRange.upperBound, toGranularity: .day) != .orderedDescending
        else {
            return nil
        }

        let isStart = gregorianCalendar.isDate(date, inSameDayAs: selectedRange.lowerBound)
        let isEnd = gregorianCalendar.isDate(date, inSameDayAs: selectedRange.upperBound)

        switch (isStart, isEnd) {
        case (true, true):
            return .single
        case (true, false):
            return .start
        case (false, true):
            return .end
        case (false, false):
            return .middle
        }
    }
}

private struct CalendarDay: Identifiable {
    let id: String
    let date: Date?
    let dayNumber: Int
}

private enum CalendarRangePosition {
    case single
    case start
    case middle
    case end
}

private struct CalendarRangeBackground: Shape {
    let position: CalendarRangePosition

    func path(in rect: CGRect) -> Path {
        let diameter = min(rect.width, rect.height)
        let circleRect = CGRect(
            x: rect.midX - diameter / 2,
            y: rect.midY - diameter / 2,
            width: diameter,
            height: diameter
        )

        switch position {
        case .single:
            return Circle().path(in: circleRect)
        case .start:
            return Path { path in
                path.addPath(Rectangle().path(in: CGRect(
                    x: rect.midX,
                    y: circleRect.minY,
                    width: rect.maxX - rect.midX,
                    height: diameter
                )))
                path.addPath(Circle().path(in: circleRect))
            }
        case .middle:
            return Rectangle().path(in: CGRect(
                x: rect.minX,
                y: circleRect.minY,
                width: rect.width,
                height: diameter
            ))
        case .end:
            return Path { path in
                path.addPath(Rectangle().path(in: CGRect(
                    x: rect.minX,
                    y: circleRect.minY,
                    width: rect.midX - rect.minX,
                    height: diameter
                )))
                path.addPath(Circle().path(in: circleRect))
            }
        }
    }
}

private enum CalendarStyle {
    // Locale-aware very-short weekday symbols, Sunday-first (matches firstWeekday = 1).
    static var weekdaySymbols: [String] {
        Calendar(identifier: .gregorian).veryShortStandaloneWeekdaySymbols
    }

    static let cardBackground = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let primary = Color(red: 0, green: 0.48, blue: 1)
    static let secondary = Color(red: 1, green: 0.15, blue: 0.11)
    static let primaryText = Color(red: 0.17, green: 0.17, blue: 0.17)
    static let invertedText = Color(red: 0.96, green: 0.96, blue: 0.96)
    static let neutral = Color(red: 0.54, green: 0.54, blue: 0.54)
    static let disabled = Color(red: 0.89, green: 0.89, blue: 0.89)

    static let headerFont = Font.system(size: 18, weight: .bold)
    static let dayFont = Font.system(size: 18, weight: .regular)
}

private extension Text {
    func calendarHeaderText() -> some View {
        font(CalendarStyle.headerFont)
            .foregroundStyle(CalendarStyle.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private enum CalendarPreviewData {
    static let timeZone = TimeZone(secondsFromGMT: 0) ?? .current

    static var january2024: Date {
        makeDate(year: 2024, month: 1, day: 1)
    }

    static var currentDate: Date {
        makeDate(year: 2024, month: 1, day: 5)
    }

    static var selectedRange: ClosedRange<Date> {
        makeDate(year: 2024, month: 1, day: 9)...makeDate(year: 2024, month: 1, day: 11)
    }

    static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}

#Preview("Figma - January 2024") {
    MultiSelectCalendar(timeZone: CalendarPreviewData.timeZone)
        .frame(width: 361, height: 416)
        .padding()
        .background(Constants.Background)
}

#Preview("Interactive Selection") {
    MultiSelectCalendarPreviewContainer()
}

private struct MultiSelectCalendarPreviewContainer: View {
    @State private var startDate: Date? = CalendarPreviewData.makeDate(year: 2024, month: 1, day: 9)
    @State private var endDate: Date? = CalendarPreviewData.makeDate(year: 2024, month: 1, day: 11)

    var body: some View {
        MultiSelectCalendar(
            month: CalendarPreviewData.january2024,
            currentDate: CalendarPreviewData.currentDate,
            selectedRange: selectedRange,
            disabledBefore: CalendarPreviewData.currentDate,
            timeZone: CalendarPreviewData.timeZone
        ) { date in
            handleDateSelection(date)
        }
        .frame(width: 361, height: 416)
        .padding()
    }

    private var selectedRange: ClosedRange<Date>? {
        guard let startDate else { return nil }

        if let endDate {
            return min(startDate, endDate)...max(startDate, endDate)
        }

        return startDate...startDate
    }

    private func handleDateSelection(_ date: Date) {
        if startDate == nil || endDate != nil {
            startDate = date
            endDate = nil
        } else if let startDate {
            if date < startDate {
                self.startDate = date
            } else {
                endDate = date
            }
        }
    }
}
