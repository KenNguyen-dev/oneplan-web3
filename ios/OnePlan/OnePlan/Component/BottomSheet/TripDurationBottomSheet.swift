//
//  TripDurationBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 3/5/26.
//

import SwiftUI

struct TripDurationBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var startDate: Date
    @Binding var endDate: Date

    var currentDate: Date = Date()
    var timeZone: TimeZone = .current
    var visibleMonthCount: Int = 12
    var onConfirm: (Date, Date) -> Void = { _, _ in }

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date?

    private var gregorianCalendar: Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    private var currentDay: Date {
        gregorianCalendar.startOfDay(for: currentDate)
    }

    private var selectedRange: ClosedRange<Date>? {
        guard let draftEndDate else {
            return draftStartDate...draftStartDate
        }

        return min(draftStartDate, draftEndDate)...max(draftStartDate, draftEndDate)
    }

    private var displayedMonths: [Date] {
        let monthStart = startOfMonth(for: currentDay)

        return (0..<max(1, visibleMonthCount)).compactMap { offset in
            gregorianCalendar.date(byAdding: .month, value: offset, to: monthStart)
        }
    }

    init(
        startDate: Binding<Date>,
        endDate: Binding<Date>,
        currentDate: Date = Date(),
        timeZone: TimeZone = .current,
        visibleMonthCount: Int = 12,
        onConfirm: @escaping (Date, Date) -> Void = { _, _ in }
    ) {
        _startDate = startDate
        _endDate = endDate
        _draftStartDate = State(initialValue: startDate.wrappedValue)
        _draftEndDate = State(initialValue: endDate.wrappedValue)
        self.currentDate = currentDate
        self.timeZone = timeZone
        self.visibleMonthCount = visibleMonthCount
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedMonths, id: \.self) { month in
                            MultiSelectCalendar(
                                month: month,
                                currentDate: currentDay,
                                selectedRange: selectedRange,
                                disabledBefore: currentDay,
                                timeZone: timeZone,
                                onSelectDate: handleDateSelection
                            )
                            .frame(height: 416)
                        }
                    }
                    .padding(.bottom, 54)
                }
            }

            PrimaryButton(title: "Confirm") {
                confirmSelection()
                dismiss()
            }
            .padding(.horizontal, 8)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
        .onAppear {
            resetDraftSelection()
        }
    }

    private func handleDateSelection(_ date: Date) {
        let normalizedDate = gregorianCalendar.startOfDay(for: date)
        guard normalizedDate >= currentDay else { return }

        if draftEndDate != nil {
            draftStartDate = normalizedDate
            draftEndDate = nil
            return
        }

        if normalizedDate < draftStartDate {
            draftStartDate = normalizedDate
        } else if normalizedDate == draftStartDate {
            draftEndDate = nil
        } else {
            draftEndDate = normalizedDate
        }
    }

    private func confirmSelection() {
        let normalizedEndDate = draftEndDate ?? draftStartDate
        let confirmedStartDate = min(draftStartDate, normalizedEndDate)
        let confirmedEndDate = max(draftStartDate, normalizedEndDate)

        startDate = confirmedStartDate
        endDate = confirmedEndDate
        onConfirm(confirmedStartDate, confirmedEndDate)
    }

    private func resetDraftSelection() {
        draftStartDate = max(gregorianCalendar.startOfDay(for: startDate), currentDay)
        draftEndDate = max(gregorianCalendar.startOfDay(for: endDate), draftStartDate)
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = gregorianCalendar.dateComponents([.year, .month], from: date)
        return gregorianCalendar.date(from: components) ?? date
    }
}

#Preview {
    TripDurationBottomSheetPreview()
}

private struct TripDurationBottomSheetPreview: View {
    @State private var isPresented = true
    @State private var startDate = TripDurationBottomSheetPreview.makeDate(year: 2024, month: 1, day: 9)
    @State private var endDate = TripDurationBottomSheetPreview.makeDate(year: 2024, month: 1, day: 11)

    var body: some View {
        Color.clear
            .sheet(isPresented: $isPresented) {
                TripDurationBottomSheet(
                    startDate: $startDate,
                    endDate: $endDate,
                    currentDate: Self.makeDate(year: 2024, month: 1, day: 5),
                    timeZone: TimeZone(secondsFromGMT: 0) ?? .current
                )
            }
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }
}
