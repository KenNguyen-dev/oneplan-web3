//
//  RearrangeDateBottomSheet.swift
//  OnePlan
//
//  Created by ken on 22/4/26.
//

import SwiftUI

struct RearrangeDateItem: Identifiable, Equatable {
    let id: String
    let title: String
    let dayNumber: Int?
    let date: Date?
    let subtitle: String?

    init(
        id: String,
        title: String,
        dayNumber: Int? = nil,
        date: Date? = nil,
        subtitle: String? = nil
    ) {
        self.id = id
        self.title = title
        self.dayNumber = dayNumber
        self.date = date
        self.subtitle = subtitle
    }
}

struct RearrangeDateBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [RearrangeDateItem]
    var onRearrange: ([RearrangeDateItem]) -> Void = { _ in }
    var onDelete: (RearrangeDateItem) -> Void = { _ in }

    @State private var arrangedItems: [RearrangeDateItem] = []
    @State private var draggingItemId: String?
    @State private var pendingDeleteItem: RearrangeDateItem?
    @State private var rowFrames: [String: CGRect] = [:]

    private func displayTitle(for item: RearrangeDateItem) -> String {
        switch (item.date, item.dayNumber) {
        case let (date?, day?):
            return String(localized: "\(DisplayFormatters.monthDay(date)) · Day \(day)", comment: "%1$@ = date, %2$lld = day number")
        case let (date?, nil):
            return DisplayFormatters.monthDay(date)
        case let (nil, day?):
            return String(localized: "Day \(day)")
        case (nil, nil):
            return item.title
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 25)
                .padding(.horizontal, 16)

            dayList
                .padding(.top, 18)

            Spacer(minLength: 14)

//            DismissButton {
//                dismiss()
//            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
        .onAppear {
            arrangedItems = items
        }
        .onChange(of: items) { _, newValue in
            arrangedItems = newValue
        }
        .alert(
            "Delete every plan in \(pendingDeleteItem.map(displayTitle(for:)) ?? String(localized: "this day"))?",
            isPresented: Binding(
                get: { pendingDeleteItem != nil },
                set: { if !$0 { pendingDeleteItem = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeleteItem = nil
            }
            Button("Delete", role: .destructive) {
                confirmDelete()
            }
        } message: {
            Text("This will delete every plan in this day.")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Re-arrange your trip")
                .font(Font.custom("Be Vietnam Pro", size: 20))
                .lineLimit(1)
                .foregroundStyle(Constants.ContentB)

            Text("Drag to arrange or tap “Delete” to erase plan")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .lineLimit(1)
                .foregroundStyle(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var dayList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                ForEach(arrangedItems) { item in
                    dayRow(item)
                        .opacity(draggingItemId == item.id ? 0.72 : 1)
                        .background(rowFrameReader(for: item.id))
                        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: arrangedItems)
                }
            }
            .padding(.top, 2)
            .padding(.horizontal, 16)
        }
        .coordinateSpace(name: "rearrange-days")
        .onPreferenceChange(RearrangeDateRowFrameKey.self) { frames in
            rowFrames = frames
        }
    }

    private func dayRow(_ item: RearrangeDateItem) -> some View {
        HStack(spacing: 12) {
            DragHandle()
                .padding(.leading, 2)
                .padding(.trailing, 1)
                .contentShape(Rectangle())
                .gesture(reorderGesture(for: item))

            VStack(alignment: .leading, spacing: 2) {
                titleRow(for: item)

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Font.custom("Be Vietnam Pro", size: 13))
                        .tracking(-0.26)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Constants.ContentM)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                prepareDelete(item)
            } label: {
                Text("Delete")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.28)
                    .lineLimit(1)
                    .foregroundStyle(Constants.White)
                    .padding(8)
                    .background(Color(red: 0.88, green: 0.15, blue: 0.14))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Constants.Background)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func titleRow(for item: RearrangeDateItem) -> some View {
        if item.date != nil || item.dayNumber != nil {
            HStack(spacing: 6) {
                if let date = item.date {
                    Text(DisplayFormatters.monthDay(date))
                        .font(Font.beVietnamPro(15, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(Constants.ContentM)
                }
                if let day = item.dayNumber {
                    Text("Day \(day)")
                        .font(Font.beVietnamPro(17, weight: .semibold))
                        .tracking(-0.34)
                        .foregroundStyle(Constants.ContentB)
                }
            }
            .lineLimit(1)
        } else {
            Text(item.title)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .tracking(-0.3)
                .lineLimit(1)
                .foregroundStyle(Constants.ContentB)
        }
    }

    private func reorderGesture(for item: RearrangeDateItem) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("rearrange-days"))
            .onChanged { value in
                if draggingItemId == nil {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    draggingItemId = item.id
                }
                move(item, toY: value.location.y)
            }
            .onEnded { _ in
                draggingItemId = nil
                onRearrange(arrangedItems)
            }
    }

    private func rowFrameReader(for id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: RearrangeDateRowFrameKey.self,
                value: [id: proxy.frame(in: .named("rearrange-days"))]
            )
        }
    }

    private func move(_ item: RearrangeDateItem, toY yPosition: CGFloat) {
        guard let fromIndex = arrangedItems.firstIndex(of: item) else { return }
        guard let targetId = rowFrames.first(where: { _, frame in
            frame.minY <= yPosition && yPosition <= frame.maxY
        })?.key else { return }
        guard targetId != item.id,
              let toIndex = arrangedItems.firstIndex(where: { $0.id == targetId }) else { return }

        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            arrangedItems.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }
    }

    private func prepareDelete(_ item: RearrangeDateItem) {
        guard arrangedItems.count > 1 else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        pendingDeleteItem = item
    }

    private func confirmDelete() {
        guard let item = pendingDeleteItem else { return }
        arrangedItems.removeAll { $0.id == item.id }
        onDelete(item)
        pendingDeleteItem = nil
    }
}

private struct DragHandle: View {
    var body: some View {
        VStack(spacing: 4.6) {
            handleLine
            handleLine
            handleLine
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private var handleLine: some View {
        Rectangle()
            .fill(Constants.ContentM)
            .frame(width: 15, height: 1)
    }
}

private struct RearrangeDateRowFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newValue in newValue })
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            RearrangeDateBottomSheet(
                items: [
                    RearrangeDateItem(id: "1", title: "Day 1"),
                    RearrangeDateItem(id: "2", title: "Day 2"),
                    RearrangeDateItem(id: "3", title: "Day 2"),
                    RearrangeDateItem(id: "4", title: "Day 2"),
                    RearrangeDateItem(id: "5", title: "Day 2"),
                    RearrangeDateItem(id: "6", title: "Day 2"),
                    RearrangeDateItem(id: "7", title: "Day 2"),
                    RearrangeDateItem(id: "8", title: "Day 2"),
                    RearrangeDateItem(id: "9", title: "Day 2"),
                ]
            )
        }
}
