//
//  TripDatesBottomSheet.swift
//  OnePlan
//

import SwiftUI

struct TripDatesBottomSheet: View {
    @Binding var isPresented: Bool
    let initialStartDate: Date?
    let initialEndDate: Date?
    let minimumStartDate: Date?
    let onConfirm: (Date, Date) -> Void

    private static let sheetHeight: CGFloat = 620
    @State private var draftStartDate: Date?
    @State private var draftEndDate: Date?

    private var gregorianCalendar: Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    private var minimumAllowedStartDate: Date {
        let today = gregorianCalendar.startOfDay(for: .now)
        guard let minimumStartDate else { return today }
        return max(gregorianCalendar.startOfDay(for: minimumStartDate), today)
    }

    private var displayedMonths: [Date] {
        let monthStart = startOfMonth(for: minimumAllowedStartDate)
        return (0..<12).compactMap { offset in
            gregorianCalendar.date(byAdding: .month, value: offset, to: monthStart)
        }
    }

    private var selectedRange: ClosedRange<Date>? {
        guard let draftStartDate else { return nil }
        if let draftEndDate {
            return min(draftStartDate, draftEndDate)...max(draftStartDate, draftEndDate)
        }
        return draftStartDate...draftStartDate
    }

    private var canConfirm: Bool {
        draftStartDate != nil
    }

    var body: some View {
        GeometryReader { geometry in
            BottomSheet(
                isPresented: $isPresented,
                sheetHeight: min(geometry.size.height, Self.sheetHeight),
                backdropOpacity: 0.15,
                enablesPullToDismiss: true
            ) { dismiss in
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Capsule()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 35, height: 4.9)
                            .padding(.top, 12)

                        Text("Choose trip dates")
                            .font(Font.beVietnamPro(16, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(displayedMonths, id: \.self) { month in
                                    MultiSelectCalendar(
                                        month: month,
                                        currentDate: gregorianCalendar.startOfDay(for: .now),
                                        selectedRange: selectedRange,
                                        disabledBefore: minimumAllowedStartDate,
                                        timeZone: .current,
                                        onSelectDate: handleDateSelection
                                    )
                                    .frame(height: 416)
                                }
                            }
                            .padding(.bottom, 84)
                        }
                    }

                    PrimaryButton(title: "Confirm") {
                        guard let start = draftStartDate else { return }
                        let end = draftEndDate ?? start
                        let confirmedStart = min(start, end)
                        let confirmedEnd = max(start, end)
                        onConfirm(confirmedStart, confirmedEnd)
                        dismiss()
                    }
                    .disabled(!canConfirm)
                    .opacity(canConfirm ? 1 : 0.5)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .onAppear { primeDraftSelection() }
    }

    private func primeDraftSelection() {
        if let initialStartDate {
            draftStartDate = max(
                gregorianCalendar.startOfDay(for: initialStartDate),
                minimumAllowedStartDate
            )
        }
        if let initialEndDate {
            draftEndDate = max(
                gregorianCalendar.startOfDay(for: initialEndDate),
                draftStartDate ?? minimumAllowedStartDate
            )
        }
    }

    private func handleDateSelection(_ date: Date) {
        let normalized = gregorianCalendar.startOfDay(for: date)
        guard normalized >= minimumAllowedStartDate else { return }

        if draftStartDate == nil || draftEndDate != nil {
            draftStartDate = normalized
            draftEndDate = nil
            return
        }

        guard let currentStart = draftStartDate else { return }
        if normalized < currentStart {
            draftStartDate = normalized
        } else if normalized == currentStart {
            draftEndDate = nil
        } else {
            draftEndDate = normalized
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = gregorianCalendar.dateComponents([.year, .month], from: date)
        return gregorianCalendar.date(from: components) ?? date
    }
}

#Preview {
    TripDatesBottomSheet(
        isPresented: .constant(true),
        initialStartDate: nil,
        initialEndDate: nil,
        minimumStartDate: nil,
        onConfirm: { _, _ in }
    )
}
