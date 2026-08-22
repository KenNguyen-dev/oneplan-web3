//
//  StartTripBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 17/4/26.
//

import SwiftUI

struct StartTripBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var startDate: Date
    @Binding var endDate: Date?
    @Binding var timeZone: TimeZone

    var buttonTitle: String
    var thumbnailImageName: String?
    var thumbnailUrl: String?
    var thumbnailImage: UIImage?
    var minimumStartDate: Date?
    var onStartTrip: () -> Void

    private static let sheetHeight: CGFloat = 452
    @State private var isShowingDatePicker = false
    @State private var isShowingTimeZonePicker = false
    @State private var hasSelectedTripDate = false
    @State private var draftStartDate: Date?
    @State private var draftEndDate: Date?
    @State private var selectedStartDate: Date?
    @State private var selectedEndDate: Date?

    private var gregorianCalendar: Foundation.Calendar {
        var calendar = Foundation.Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 1
        return calendar
    }

    private var currentDay: Date {
        gregorianCalendar.startOfDay(for: .now)
    }

    private var selectedRange: ClosedRange<Date>? {
        guard let draftStartDate else {
            return nil
        }

        if let draftEndDate {
            return min(draftStartDate, draftEndDate)...max(draftStartDate, draftEndDate)
        }

        return draftStartDate...draftStartDate
    }

    private var displayedMonths: [Date] {
        let monthStart = startOfMonth(for: minimumAllowedStartDate)

        return (0..<12).compactMap { offset in
            gregorianCalendar.date(byAdding: .month, value: offset, to: monthStart)
        }
    }

    private var hasConfirmedTripDateRange: Bool {
        hasSelectedTripDate && selectedStartDate != nil && selectedEndDate != nil
    }

    init(
        startDate: Binding<Date>,
        endDate: Binding<Date?> = .constant(nil),
        timeZone: Binding<TimeZone>,
        buttonTitle: String = String(localized: "Start trip"),
        thumbnailImageName: String? = "defaultTripPlaceholder",
        thumbnailUrl: String? = nil,
        thumbnailImage: UIImage? = nil,
        minimumStartDate: Date? = nil,
        onStartTrip: @escaping () -> Void = {}
    ) {
        _startDate = startDate
        _endDate = endDate
        _timeZone = timeZone
        _hasSelectedTripDate = State(initialValue: endDate.wrappedValue != nil)
        _selectedStartDate = State(
            initialValue: endDate.wrappedValue == nil ? nil : startDate.wrappedValue
        )
        _selectedEndDate = State(initialValue: endDate.wrappedValue)
        self.buttonTitle = buttonTitle
        self.thumbnailImageName = thumbnailImageName
        self.thumbnailUrl = thumbnailUrl
        self.thumbnailImage = thumbnailImage
        self.minimumStartDate = minimumStartDate
        self.onStartTrip = onStartTrip
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.top, 24)

            dateSection
                .padding(.top, 28)
                .padding(.horizontal, 16)

            PrimaryButton(title: "\(buttonTitle)", action: onStartTrip)
                .disabled(!hasConfirmedTripDateRange)
                .padding(.top, 24)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(Self.sheetHeight)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(36)
        .sheet(isPresented: $isShowingDatePicker) {
            datePickerSheet
        }
        .sheet(isPresented: $isShowingTimeZonePicker) {
            timeZonePickerSheet
        }
        .onAppear {
            clampStartDateIfNeeded()
        }
        .onChange(of: minimumAllowedStartDate) { _, _ in
            clampStartDateIfNeeded()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 19) {
            MarketplaceThumbnailImageHolder(
                thumbnailImageName: thumbnailImageName,
                thumbnailUrl: thumbnailUrl,
                thumbnailImage: thumbnailImage,
                size: 100
            )

            VStack(spacing: 8) {
                Text("Start your trip now")
                    .font(Font.custom("Be Vietnam Pro", size: 20))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-1)

                Text("or pick your start date")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .tracking(-0.7)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var dateSection: some View {
        VStack(spacing: 8) {
            dateButton

//            timeZoneRow

            helperText
                .padding(.horizontal, 8)
        }
    }

    private var dateButton: some View {
        Button {
            resetDraftSelection()
            isShowingDatePicker = true
        } label: {
            fieldCard {
                HStack(spacing: 6) {
                    dateLeadingIcon

                    Text("Trip Dates")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.28)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(startDateLabel)
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundStyle(Constants.ContentB)
                            .tracking(-0.8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Constants.ContentM.opacity(0.85))
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var timeZoneRow: some View {
        Button {
            isShowingTimeZonePicker = true
        } label: {
            fieldCard {
                HStack(spacing: 6) {
                    Image("planetBlue")
                        .renderingMode(.original)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)

                    Text("Time zone")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.ContentB)
                        .tracking(-0.28)

                    Spacer(minLength: 0)

                    HStack(spacing: 6) {
                        Text(timeZoneLabel)
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundStyle(Constants.ContentB)
                            .tracking(-0.8)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Constants.ContentM.opacity(0.85))
                            .frame(width: 24, height: 24)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var dateLeadingIcon: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Constants.Purple500)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Constants.White)
            }
    }

    private var helperText: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(
                "After you start your trip, we will send you reminders about what to do and where to go."
            )
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundColor(Constants.Neutral950)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)

            Text(
                "Note: Your trip must be planned based on the timezone of your destination."
            )
            .font(Font.custom("Be Vietnam Pro", size: 14))
            .foregroundColor(Constants.Neutral400)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 0)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var datePickerSheet: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                Text("Select Date")
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundColor(Constants.ContentB)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(displayedMonths, id: \.self) { month in
                            MultiSelectCalendar(
                                month: month,
                                currentDate: currentDay,
                                selectedRange: selectedRange,
                                disabledBefore: minimumAllowedStartDate,
                                timeZone: timeZone,
                                onSelectDate: handleDateSelection
                            )
                            .frame(height: 416)
                        }
                    }
                    .padding(.bottom, 84)
                }
            }

            PrimaryButton(title: "Confirm") {
                confirmDateSelection()
                isShowingDatePicker = false
            }
            .disabled(draftStartDate == nil)
            .opacity(draftStartDate == nil ? 0.5 : 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(620)])
        .presentationDragIndicator(.visible)
    }

    private var timeZonePickerSheet: some View {
        VStack(spacing: 0) {
            Text("Select UTC")
                .font(
                    Font.beVietnamPro(16, weight: .medium)
                )
                .foregroundStyle(Constants.ContentB)
                .padding(.top, 16)

            Picker("", selection: timeZoneOffsetSelection) {
                ForEach(utcOffsetOptions, id: \.self) { offset in
                    Text(Self.utcLabel(for: offset))
                        .tag(offset)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(height: 180)

            Button {
                isShowingTimeZonePicker = false
            } label: {
                Text("Done")
                    .font(
                        Font.beVietnamPro(16, weight: .medium)
                    )
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Constants.BlueBase)
                    .cornerRadius(22)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
    }

    private var startDateLabel: String {
        guard hasSelectedTripDate else {
            return String(localized: "Select")
        }

        let selectedStartDate = selectedStartDate ?? startDate

        guard
            let selectedEndDate,
            !gregorianCalendar.isDate(selectedStartDate, inSameDayAs: selectedEndDate)
        else {
            return dateLabel(for: selectedStartDate)
        }

        return String(localized: "\(dateLabel(for: selectedStartDate)) - \(dateLabel(for: selectedEndDate))", comment: "%1$@ = start date, %2$@ = end date")
    }

    private func dateLabel(for date: Date) -> String {
        if gregorianCalendar.isDateInToday(date) {
            return String(localized: "Today")
        }

        if gregorianCalendar.isDateInYesterday(date) {
            return String(localized: "Yesterday")
        }

        return DisplayFormatters.monthDay(date)
    }

    private var dayOneDateText: String {
        Self.dayOneDateFormatter.string(from: startDate)
    }

    private var timeZoneLabel: String {
        Self.utcLabel(for: timeZone.secondsFromGMT(for: startDate))
    }

    private var timeZoneOffsetSelection: Binding<Int> {
        Binding(
            get: {
                timeZone.secondsFromGMT(for: startDate)
            },
            set: { newValue in
                if let selectedTimeZone = TimeZone(secondsFromGMT: newValue) {
                    timeZone = selectedTimeZone
                }
            }
        )
    }

    private var utcOffsetOptions: [Int] {
        var offsets = Set(
            TimeZone.knownTimeZoneIdentifiers.compactMap { identifier in
                TimeZone(identifier: identifier)?.secondsFromGMT(for: startDate)
            }
        )
        offsets.insert(timeZone.secondsFromGMT(for: startDate))
        return offsets.sorted()
    }

    private var minimumAllowedStartDate: Date {
        let today = gregorianCalendar.startOfDay(for: .now)

        guard let minimumStartDate else {
            return today
        }

        return max(gregorianCalendar.startOfDay(for: minimumStartDate), today)
    }

    private func clampStartDateIfNeeded() {
        let minimumAllowedStartDate = minimumAllowedStartDate
        if startDate < minimumAllowedStartDate {
            startDate = minimumAllowedStartDate
        }
    }

    private func handleDateSelection(_ date: Date) {
        let normalizedDate = gregorianCalendar.startOfDay(for: date)
        guard normalizedDate >= minimumAllowedStartDate else { return }

        if draftStartDate == nil || draftEndDate != nil {
            draftStartDate = normalizedDate
            draftEndDate = nil
            return
        }

        guard let draftStartDate else { return }

        if normalizedDate < draftStartDate {
            self.draftStartDate = normalizedDate
        } else if normalizedDate == draftStartDate {
            draftEndDate = nil
        } else {
            draftEndDate = normalizedDate
        }
    }

    private func confirmDateSelection() {
        guard let draftStartDate else { return }

        let normalizedEndDate = draftEndDate ?? draftStartDate
        let confirmedStartDate = min(draftStartDate, normalizedEndDate)
        let confirmedEndDate = max(draftStartDate, normalizedEndDate)

        selectedStartDate = confirmedStartDate
        selectedEndDate = confirmedEndDate
        startDate = confirmedStartDate
        endDate = confirmedEndDate
        hasSelectedTripDate = true
    }

    private func resetDraftSelection() {
        guard hasSelectedTripDate else {
            draftStartDate = nil
            draftEndDate = nil
            return
        }

        draftStartDate = max(
            gregorianCalendar.startOfDay(for: selectedStartDate ?? startDate),
            minimumAllowedStartDate
        )
        draftEndDate = selectedEndDate.map {
            max(gregorianCalendar.startOfDay(for: $0), draftStartDate ?? minimumAllowedStartDate)
        }
    }

    private func startOfMonth(for date: Date) -> Date {
        let components = gregorianCalendar.dateComponents([.year, .month], from: date)
        return gregorianCalendar.date(from: components) ?? date
    }

    private static let dayOneDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()

    private static func utcLabel(for secondsFromGMT: Int) -> String {
        let absoluteOffset = abs(secondsFromGMT)
        let hours = absoluteOffset / 3600
        let minutes = (absoluteOffset % 3600) / 60
        let sign = secondsFromGMT >= 0 ? "+" : "-"

        if minutes == 0 {
            return "UTC \(sign)\(hours)"
        }

        return String(format: "UTC %@%d:%02d", sign, hours, minutes)
    }

    @ViewBuilder
    private func fieldCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Constants.Surface)
            .clipShape(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            StartTripBottomSheet(
                startDate: .constant(.now),
                timeZone: .constant(.current)
            )
        }
}
