//
//  MarketPlanSection.swift
//  OnePlan
//
//  Created by Codex on 26/3/26.
//

import SwiftUI

enum MarketPlanDisplayMode {
    case preview  // max 4 items, 4th blurred, no day tabs (legacy/#Preview only)
    case previewWithDays  // day tabs + per-day cap: first 3 + blurred 4th (non-Pro)
    case full  // all items, day tabs, no blur (Pro / seller)
}

private struct MarketPlanEntry {
    let title: String
    let location: String
    let markerColor: Color
    let description: String?
    let planItem: PlanItemDto
}

private struct MarketPlanTimelineSlot {
    let timeLabel: String
    let entries: [MarketRenderedPlanEntry]
}

private struct MarketRenderedPlanEntry: Identifiable {
    let id: Int
    let entry: MarketPlanEntry
    let isBlurred: Bool
}

private struct IndexedMarketPlanSlot: Identifiable {
    let id: Int
    let slot: MarketPlanTimelineSlot
}

private struct MarketDottedDivider: View {
    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: 1)
            .overlay(alignment: .center) {
                GeometryReader { proxy in
                    Path { path in
                        let y = proxy.size.height / 2
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                    .stroke(
                        Constants.Neutral200.opacity(0.85),
                        style: StrokeStyle(
                            lineWidth: 1,
                            lineCap: .round,
                            dash: [3, 3]
                        )
                    )
                }
            }
    }
}

private struct MarketPlanStripImage: HeroLightboxItem {
    let id: Int
    let image: UIImage?
    let urlString: String?

    static func == (lhs: MarketPlanStripImage, rhs: MarketPlanStripImage) -> Bool {
        lhs.id == rhs.id && lhs.urlString == rhs.urlString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(urlString)
    }
}

private struct MarketPlanImageStrip: View {
    private enum Metrics {
        static let imageSize: CGFloat = 90
        static let spacing: CGFloat = 4
        static let cornerRadius: CGFloat = 8
    }

    let images: [UIImage]
    let imageUrls: [String]

    @State private var config: HeroLightboxConfig<MarketPlanStripImage> = .init()

    private var stripImages: [MarketPlanStripImage] {
        if !images.isEmpty {
            return images.enumerated().map { index, image in
                MarketPlanStripImage(id: index, image: image, urlString: nil)
            }
        }

        return imageUrls.enumerated().map { index, imageUrl in
            MarketPlanStripImage(id: index, image: nil, urlString: imageUrl)
        }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.spacing) {
                ForEach(stripImages, id: \.id) { item in
                    Rectangle()
                        .foregroundStyle(.clear)
                        .overlay {
                            GeometryReader { proxy in
                                let rect = proxy.frame(in: .global)
                                let updatedRect: CGRect? = config.selectedItem == item ? rect : nil

                                thumbnail(for: item)
                                    .opacity(config.selectedItem == item ? 0 : 1)
                                    .frame(
                                        width: Metrics.imageSize,
                                        height: Metrics.imageSize
                                    )
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: Metrics.cornerRadius,
                                            style: .continuous
                                        )
                                    )
                                    .contentShape(.rect)
                                    .onTapGesture {
                                        config.selectedItem = item
                                        config.sourceLocation = rect
                                        withoutAnimation {
                                            config.showFullScreenCover = true
                                        }
                                    }
                                    .onChange(of: updatedRect) { _, newValue in
                                        if let newValue {
                                            config.sourceLocation = newValue
                                        }
                                    }
                            }
                        }
                        .frame(
                            width: Metrics.imageSize,
                            height: Metrics.imageSize
                        )
                        .clipped()
                        .contentShape(.rect)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: Metrics.imageSize)
        .scrollPosition(id: $config.sourceScrollID)
        .fullScreenCover(isPresented: $config.showFullScreenCover) {
            config.selectedItem = nil
        } content: {
            HeroLightboxDetailView(
                config: $config,
                data: stripImages
            ) { item, isExpanded, _, _ in
                lightboxImage(for: item, isExpanded: isExpanded)
            } overlay: { _, _, _, _ in
                EmptyView()
            }
        }
        .onChange(of: config.selectedItem) { oldValue, newValue in
            if let newValue, oldValue != nil {
                config.sourceScrollID = newValue.id
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for item: MarketPlanStripImage) -> some View {
        if let image = item.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else if let urlString = item.urlString {
            CachedRemoteImage(
                url: URL(string: urlString),
                targetSize: CGSize(
                    width: Metrics.imageSize,
                    height: Metrics.imageSize
                )
            ) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Rectangle()
                    .fill(Constants.Neutral100)
            }
        } else {
            Rectangle()
                .fill(Constants.Neutral100)
        }
    }

    @ViewBuilder
    private func lightboxImage(for item: MarketPlanStripImage, isExpanded: Bool) -> some View {
        if let image = item.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: isExpanded ? .fit : .fill)
        } else if let urlString = item.urlString {
            CachedRemoteImage(url: URL(string: urlString)) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: isExpanded ? .fit : .fill)
            } placeholder: {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            Rectangle()
                .fill(Constants.Neutral100)
        }
    }
}

private struct MarketPlanItemCard: View {
    let title: String
    let location: String
    let markerColor: Color
    let description: String?
    let images: [UIImage]
    let imageUrls: [String]
    let canAddImagePlaceholder: Bool

    private var descriptionText: String? {
        let trimmed = (description ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .center, spacing: 6) {
                    Circle()
                        .fill(markerColor)
                        .frame(width: 12, height: 12)

                    Text(title)
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .tracking(-0.64)
                        .foregroundStyle(Constants.ContentB)
                        .lineLimit(1)
                }

                HStack(alignment: .center, spacing: 3) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Constants.ContentM)

                    Text(location.isEmpty ? "No location" : location)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .tracking(-0.6)
                        .foregroundStyle(Constants.ContentM)
                        .lineLimit(1)
                }
            }

            if let descriptionText {
                MarketDottedDivider()

                Text(descriptionText)
                    .font(Font.custom("Be Vietnam Pro", size: 13))
                    .tracking(-0.39)
                    .foregroundStyle(Constants.ContentM)
                    .lineLimit(2)
            }

            if !images.isEmpty || !imageUrls.isEmpty {
                MarketPlanImageStrip(images: images, imageUrls: imageUrls)
            } else if canAddImagePlaceholder {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Constants.Neutral100)
                    .frame(width: 90, height: 90)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(Constants.Neutral700)
                    }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 17.9, x: 0, y: 0)
    }
}

struct MarketPlanSection: View {
    let planItems: [PlanItemDto]
    let mode: MarketPlanDisplayMode
    let availableDayNumbers: [Int]
    let durationDays: Int
    let canAddDay: Bool
    let showEmptyImagePlaceholder: Bool
    let planItemImagesById: [Int: [UIImage]]
    let planItemImageUrlsById: [Int: [String]]
    let dayNumberForPlanItem: ((PlanItemDto) -> Int?)?
    let onPlanTapped: ((PlanItemDto) -> Void)?
    let onLockedTapped: (() -> Void)?
    let onAddPlanTapped: ((Int) -> Void)?
    let onAddDay: (() -> Void)?
    let onDeleteDay: ((Int) -> Void)?

    @State private var selectedDay: Int = 1
    @State private var dayToDelete: Int?

    init(
        planItems: [PlanItemDto] = [],
        mode: MarketPlanDisplayMode = .preview,
        availableDayNumbers: [Int] = [],
        durationDays: Int = 1,
        canAddDay: Bool = false,
        showEmptyImagePlaceholder: Bool = false,
        planItemImagesById: [Int: [UIImage]] = [:],
        planItemImageUrlsById: [Int: [String]] = [:],
        dayNumberForPlanItem: ((PlanItemDto) -> Int?)? = nil,
        onPlanTapped: ((PlanItemDto) -> Void)? = nil,
        onLockedTapped: (() -> Void)? = nil,
        onAddPlanTapped: ((Int) -> Void)? = nil,
        onAddDay: (() -> Void)? = nil,
        onDeleteDay: ((Int) -> Void)? = nil
    ) {
        self.planItems = planItems
        self.mode = mode
        self.availableDayNumbers = availableDayNumbers.isEmpty
            ? Array(1...max(1, durationDays))
            : availableDayNumbers
        self.durationDays = max(1, durationDays)
        self.canAddDay = canAddDay
        self.showEmptyImagePlaceholder = showEmptyImagePlaceholder
        self.planItemImagesById = planItemImagesById
        self.planItemImageUrlsById = planItemImageUrlsById
        self.dayNumberForPlanItem = dayNumberForPlanItem
        self.onPlanTapped = onPlanTapped
        self.onLockedTapped = onLockedTapped
        self.onAddPlanTapped = onAddPlanTapped
        self.onAddDay = onAddDay
        self.onDeleteDay = onDeleteDay
    }

    /// Maps each unique planDate to a sequential day number (compact — gaps skipped)
    private var dateToDayNumber: [String: Int] {
        let uniqueDates = Set(planItems.compactMap(\.planDate)).sorted()
        var mapping: [String: Int] = [:]
        for (index, date) in uniqueDates.enumerated() {
            mapping[date] = index + 1
        }
        return mapping
    }

    private var itemsForCurrentView: [PlanItemDto] {
        switch mode {
        case .preview:
            return planItems
        case .full, .previewWithDays:
            let mapping = dateToDayNumber
            let resolver = dayNumberForPlanItem ?? { item in
                guard let planDate = item.planDate else { return nil }
                return mapping[planDate]
            }
            return planItems.filter { resolver($0) == selectedDay }
        }
    }

    private var timeline: [MarketPlanTimelineSlot] {
        struct TimedMarketPlanEntry {
            let hour: Int
            let minute: Int
            let entry: MarketPlanEntry
        }

        let timedEntries: [TimedMarketPlanEntry] =
            itemsForCurrentView.compactMap { item in
                guard let (hour, minute) = parseHourMinute(item.startTime)
                else { return nil }
                let entry = MarketPlanEntry(
                    title: item.title,
                    location: item.location ?? "",
                    markerColor: item.category.flatMap {
                        CategoryChip.Category(apiValue: $0.value1.rawValue)?
                            .selectedBackgroundColor
                    } ?? Constants.Warning500,
                    description: item.description,
                    planItem: item
                )
                return TimedMarketPlanEntry(
                    hour: hour,
                    minute: minute,
                    entry: entry
                )
            }

        let sortedEntries = timedEntries.sorted { lhs, rhs in
            if lhs.hour != rhs.hour { return lhs.hour < rhs.hour }
            if lhs.minute != rhs.minute { return lhs.minute < rhs.minute }
            if lhs.entry.planItem.sortOrder != rhs.entry.planItem.sortOrder {
                return lhs.entry.planItem.sortOrder
                    < rhs.entry.planItem.sortOrder
            }
            return lhs.entry.planItem.id < rhs.entry.planItem.id
        }

        let isLimited = mode == .preview || mode == .previewWithDays
        let entriesToRender =
            isLimited ? Array(sortedEntries.prefix(4)) : sortedEntries

        var entriesByHour: [Int: [MarketPlanEntry]] = [:]
        for timedEntry in entriesToRender {
            entriesByHour[timedEntry.hour, default: []].append(timedEntry.entry)
        }

        var runningEntryIndex = 0
        return (0...23).compactMap { hour in
            guard let entries = entriesByHour[hour], !entries.isEmpty else {
                return nil
            }
            let renderedEntries = entries.map { entry in
                defer { runningEntryIndex += 1 }
                return MarketRenderedPlanEntry(
                    id: runningEntryIndex,
                    entry: entry,
                    isBlurred: isLimited && runningEntryIndex == 3
                )
            }

            return MarketPlanTimelineSlot(
                timeLabel: String(format: "%02d:00", hour),
                entries: renderedEntries
            )
        }
    }

    private func parseHourMinute(_ startTime: String?) -> (Int, Int)? {
        guard let startTime else { return nil }
        let trimmed = startTime.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count >= 2,
            let hour = Int(parts[0]),
            let minute = Int(parts[1]),
            (0...23).contains(hour),
            (0...59).contains(minute)
        else {
            return nil
        }
        return (hour, minute)
    }

    private var indexedTimeline: [IndexedMarketPlanSlot] {
        timeline.enumerated().map {
            IndexedMarketPlanSlot(id: $0.offset, slot: $0.element)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if mode != .preview {
                dayChips
            }

            if indexedTimeline.isEmpty && mode != .preview {
                Text("No plans for this day")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentM)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                timelineContent
            }

            if mode == .full, let onAddPlanTapped {
                PrimaryButton(title: "New Plan") {
                    onAddPlanTapped(selectedDay)
                }
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 12)
        .onAppear {
            guard !availableDayNumbers.contains(selectedDay) else { return }
            selectedDay = availableDayNumbers.first ?? 1
        }
        .onChange(of: availableDayNumbers) { _, newValue in
            guard !newValue.contains(selectedDay) else { return }
            selectedDay = newValue.first ?? 1
        }
        .alert(
            "Delete Day \(dayToDelete ?? 0)?",
            isPresented: Binding(
                get: { dayToDelete != nil },
                set: { if !$0 { dayToDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { dayToDelete = nil }
            Button("Delete", role: .destructive) {
                if let day = dayToDelete {
                    onDeleteDay?(day)
                    if selectedDay == day {
                        selectedDay = max(day - 1, 1)
                    } else if selectedDay > day {
                        selectedDay -= 1
                    }
                }
                dayToDelete = nil
            }
        } message: {
            Text("All plans on Day \(dayToDelete ?? 0) will be deleted. Plans on later days will be moved up.")
        }
    }

    private var canDeleteDay: Bool {
        availableDayNumbers.count > 1 && onDeleteDay != nil
    }

    private var shouldShowAddDay: Bool {
        onAddDay != nil && canAddDay
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(availableDayNumbers, id: \.self) { day in
                    Text("Day \(day)")
                        .font(Font.beVietnamPro(15, weight: .medium))
                        .foregroundColor(
                            selectedDay == day ? Constants.White : Constants.ContentB
                        )
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            selectedDay == day ? Constants.BlueBase : Constants.Surface
                        )
                        .cornerRadius(17)
                        .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
                        .onTapGesture {
                            selectedDay = day
                        }
                        .onLongPressGesture(minimumDuration: 0.1) {
                            if canDeleteDay {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                dayToDelete = day
                            }
                        }
                }

                if shouldShowAddDay {
                    Button {
                        onAddDay?()
                    } label: {
                        Text("+ add")
                            .font(Font.beVietnamPro(15, weight: .medium))
                            .foregroundColor(Constants.ContentB)
                            .padding(.horizontal, 16)
                            .frame(height: 34)
                            .background(Constants.Surface)
                            .cornerRadius(17)
                            .shadow(color: .black.opacity(0.06), radius: 5, x: 0, y: 1)
                }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private var timelineContent: some View {
        VStack(spacing: 14) {
            SwiftUI.ForEach(indexedTimeline, id: \.id) { item in
                HStack(alignment: .top, spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.slot.timeLabel)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundStyle(Constants.ContentM)
                            .frame(width: 44, alignment: .leading)

                        Rectangle()
                            .fill(Constants.ContentL.opacity(0.55))
                            .frame(width: 24, height: 1)
                    }
                    .padding(.top, 6)

                    VStack(spacing: 10) {
                        SwiftUI.ForEach(item.slot.entries, id: \.id) {
                            renderedEntry in
                            Button {
                                if renderedEntry.isBlurred {
                                    onLockedTapped?()
                                } else {
                                    onPlanTapped?(
                                        renderedEntry.entry.planItem
                                    )
                                }
                            } label: {
                                MarketPlanItemCard(
                                    title: renderedEntry.entry.title,
                                    location: renderedEntry.entry.location,
                                    markerColor: renderedEntry.entry
                                        .markerColor,
                                    description: renderedEntry.entry
                                        .description,
                                    images: planItemImagesById[
                                        renderedEntry.entry.planItem.id
                                    ] ?? [],
                                    imageUrls: planItemImageUrlsById[
                                        renderedEntry.entry.planItem.id
                                    ] ?? [],
                                    canAddImagePlaceholder:
                                        showEmptyImagePlaceholder
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .blur(radius: renderedEntry.isBlurred ? 6 : 0)
                            .allowsHitTesting(
                                renderedEntry.isBlurred
                                    ? (onLockedTapped != nil) : true
                            )
                        }
                    }
                }
            }
        }
    }
}

#Preview("Preview Mode") {
    let sampleItems: [PlanItemDto] = [
        .init(
            id: 101,
            tripId: 1,
            planDate: "2026-03-26",
            title: "Đón bình minh",
            description: nil,
            location: "Đồi Măng Lin - Phường 22 Đà Lạt",
            startTime: "09:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 0,
            createdAt: "2026-03-26T00:00:00Z",
            members: []
        ),
        .init(
            id: 102,
            tripId: 1,
            planDate: "2026-03-26",
            title: "Ăn trưa",
            description: nil,
            location: "Lẩu gà á é Tao Ngộ - 79 Chu Văn An",
            startTime: "12:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 1,
            createdAt: "2026-03-26T00:00:00Z",
            members: []
        ),
        .init(
            id: 103,
            tripId: 1,
            planDate: "2026-03-26",
            title: "Cà phê chiều",
            description: nil,
            location: "Cà phê Vợt - 330/2 Phan Đình Phùng",
            startTime: "13:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 2,
            createdAt: "2026-03-26T00:00:00Z",
            members: []
        ),
        .init(
            id: 104,
            tripId: 1,
            planDate: "2026-03-26",
            title: "Grocery",
            description: nil,
            location: "Al Barsha, Dubai, UAE",
            startTime: "14:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 3,
            createdAt: "2026-03-26T00:00:00Z",
            members: []
        ),
    ]

    MarketPlanSection(planItems: sampleItems)
}

#Preview("Full Mode with Day Tabs") {
    let sampleItems: [PlanItemDto] = [
        .init(
            id: 1,
            tripId: 1,
            planDate: "2026-03-28",
            title: "Đón bình minh",
            description: "Ngắm bình minh trên đồi",
            location: "Đồi Măng Lin",
            startTime: "06:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 0,
            createdAt: "2026-03-28T00:00:00Z",
            members: []
        ),
        .init(
            id: 2,
            tripId: 1,
            planDate: "2026-03-28",
            title: "Ăn sáng",
            description: nil,
            location: "Bánh mì Đà Lạt",
            startTime: "08:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 1,
            createdAt: "2026-03-28T00:00:00Z",
            members: []
        ),
        .init(
            id: 3,
            tripId: 1,
            planDate: "2026-03-29",
            title: "Thác Datanla",
            description: nil,
            location: "Thác Datanla",
            startTime: "09:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 0,
            createdAt: "2026-03-29T00:00:00Z",
            members: []
        ),
        .init(
            id: 4,
            tripId: 1,
            planDate: "2026-04-01",
            title: "Chợ đêm",
            description: nil,
            location: "Chợ Đà Lạt",
            startTime: "19:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 0,
            createdAt: "2026-04-01T00:00:00Z",
            members: []
        ),
    ]

    MarketPlanSection(planItems: sampleItems, mode: .full, durationDays: 3)
}

#Preview("Preview With Days") {
    let sampleItems: [PlanItemDto] = (0..<6).map { index in
        .init(
            id: 300 + index,
            tripId: 1,
            planDate: "2026-03-28",
            title: "Activity \(index + 1)",
            description: nil,
            location: "Da Lat",
            startTime: String(format: "%02d:00", 6 + index),
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: index,
            createdAt: "2026-03-28T00:00:00Z",
            members: []
        )
    }

    ScrollView {
        MarketPlanSection(
            planItems: sampleItems,
            mode: .previewWithDays,
            durationDays: 1,
            onLockedTapped: { print("locked tapped") }
        )
        .padding()
    }
    .background(Constants.Background)
}

#Preview("Image Strip Lightbox") {
    let sampleItems: [PlanItemDto] = [
        .init(
            id: 201,
            tripId: 1,
            planDate: "2026-03-28",
            title: "Sunrise viewpoint",
            description: "Tap an image in the strip to preview the lightbox animation.",
            location: "Da Lat hills",
            startTime: "06:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 0,
            createdAt: "2026-03-28T00:00:00Z",
            members: []
        ),
        .init(
            id: 202,
            tripId: 1,
            planDate: "2026-03-28",
            title: "Coffee stop",
            description: "Second strip verifies each card keeps its own gallery.",
            location: "Pine forest cafe",
            startTime: "09:00",
            category: nil,
            voiceUrl: nil,
            voiceDuration: nil,
            sortOrder: 1,
            createdAt: "2026-03-28T00:00:00Z",
            members: []
        ),
    ]

    ScrollView {
        MarketPlanSection(
            planItems: sampleItems,
            mode: .full,
            durationDays: 1,
            planItemImageUrlsById: [
                201: [
                    "https://images.pexels.com/photos/1266810/pexels-photo-1266810.jpeg?w=900",
                    "https://images.pexels.com/photos/3225517/pexels-photo-3225517.jpeg?w=900",
                    "https://images.pexels.com/photos/2662116/pexels-photo-2662116.jpeg?w=900",
                ],
                202: [
                    "https://images.pexels.com/photos/1037995/pexels-photo-1037995.jpeg?w=900",
                    "https://images.pexels.com/photos/2911519/pexels-photo-2911519.jpeg?w=900",
                ],
            ]
        )
        .padding()
    }
    .background(Constants.Background)
}
