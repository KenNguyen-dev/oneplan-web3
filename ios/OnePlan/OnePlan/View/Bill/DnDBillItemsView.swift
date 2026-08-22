//
//  DnDBillItemsView.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import Foundation
import SwiftUI
import UIKit

struct DnDBillItemsView: View {
    let members: [DnDBillMemberItem]
    let breakdownRows: [[DnDBillBreakdownItem]]
    /// Currency the scanned receipt amounts are denominated in. Resolved
    /// automatically by `BillSplitFlowView` (trip local → trip group →
    /// Gemini-detected → VND); there is no user override. Drives
    /// `formatPrice` and the read-only indicator at the top of the view.
    var currency: Currency = .VND
    @Binding var restaurantName: String
    var onConfirm: ([(itemName: String, amount: Double, memberUserIds: [Int])]) -> Void = { _ in }
    var onDismiss: (() -> Void)?

    @State private var breakdownCardHeight: CGFloat = 0
    @State private var memberAssignments: [UUID: [DnDBillBreakdownItem]] = [:]
    @State private var draggedItem: DnDBillBreakdownItem? = nil
    @State private var dragPosition: CGPoint = .zero
    @State private var memberFrames: [UUID: CGRect] = [:]
    @State private var hoveredMemberID: UUID? = nil

    // Split mode state
    @State private var isSplitMode: Bool = false
    @State private var selectedMemberIDs: Set<UUID> = []
    @State private var isSplitDragging: Bool = false
    @State private var splitAvatarsAtCenter: Bool = false
    @State private var isOverSplitZone: Bool = false
    @State private var containerSize: CGSize = .zero
    @State private var assignmentHistory: [AssignmentAction] = []
    @State private var remainingQuantity: [UUID: Int] = [:]

    private let columns: [GridItem] = Array(
        repeating: GridItem(.fixed(107), spacing: 15, alignment: .top),
        count: 3
    )

    // MARK: - Computed Properties

    private var selectedMembers: [DnDBillMemberItem] {
        members.filter { selectedMemberIDs.contains($0.id) }
    }

    private var containerCenter: CGPoint {
        let usableHeight = containerSize.height - breakdownCardHeight
        return CGPoint(x: containerSize.width / 2, y: usableHeight / 2)
    }

    private var computedSplitDropZoneFrame: CGRect {
        guard !selectedMembers.isEmpty else { return .zero }
        let count = CGFloat(selectedMembers.count)
        let avatarSize: CGFloat = 50
        let overlap: CGFloat = 15
        let spacing = avatarSize - overlap
        let totalWidth = avatarSize + spacing * (count - 1)
        let padding: CGFloat = 30
        return CGRect(
            x: containerCenter.x - totalWidth / 2 - padding,
            y: containerCenter.y - avatarSize / 2 - padding,
            width: totalWidth + padding * 2,
            height: avatarSize + padding * 2 + 30
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: columns, alignment: .center, spacing: 28)
                    {
                        ForEach(members) { member in
                            DnDBillMemberCell(
                                member: member,
                                isHovered: hoveredMemberID == member.id,
                                amountTag: amountTag(for: member),
                                showCheckbox: isSplitMode,
                                isSelected: selectedMemberIDs.contains(
                                    member.id
                                )
                            )
                            .onTapGesture {
                                guard isSplitMode else { return }
                                withAnimation(
                                    .spring(
                                        response: 0.25,
                                        dampingFraction: 0.8
                                    )
                                ) {
                                    if selectedMemberIDs.contains(member.id) {
                                        selectedMemberIDs.remove(member.id)
                                    } else {
                                        selectedMemberIDs.insert(member.id)
                                    }
                                }
                            }
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: MemberFrameKey.self,
                                        value: [
                                            member.id: proxy.frame(
                                                in: .named("dndContainer")
                                            )
                                        ]
                                    )
                                }
                            }
                            .opacity(splitDragOpacity(for: member))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .padding(.bottom, breakdownCardHeight)
            }

            DnDBillBreakdownCard(
                title: $restaurantName,
                rows: breakdownRows,
                remainingQuantity: remainingQuantity,
                draggedItemID: draggedItem?.id,
                isSplitMode: isSplitMode,
                onToggleSplit: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85))
                    {
                        isSplitMode.toggle()
                        if !isSplitMode {
                            selectedMemberIDs.removeAll()
                        }
                    }
                },
                hasUndoHistory: !assignmentHistory.isEmpty,
                onUndo: performUndo,
                onReset: performReset,
                onDragChanged: handleDragChanged,
                onDragEnded: handleDragEnded
            )
            .padding(.horizontal, 16)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: DnDBillBreakdownCardHeightKey.self,
                        value: proxy.size.height
                    )
                }
            }
        }
        // Split mode: animated avatar overlay
        .overlay {
            if isSplitDragging {
                ZStack {
                    // Dashed drop zone background + label
                    if splitAvatarsAtCenter {
                        splitDropZoneIndicator
                    }

                    // Avatars animating from grid → center
                    ForEach(
                        Array(selectedMembers.enumerated()),
                        id: \.element.id
                    ) { index, member in
                        let gridPos = memberFrameCenter(for: member.id)
                        let clusterPos = clusterPosition(
                            index: index,
                            total: selectedMembers.count
                        )

                        DnDBillAvatarImage(imageURL: member.imageURL)
                            .frame(width: 107, height: 107)
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: 33.513,
                                    style: .continuous
                                )
                            )
                            .overlay {
                                if splitAvatarsAtCenter {
                                    RoundedRectangle(
                                        cornerRadius: .infinity,
                                        style: .continuous
                                    )
                                    .stroke(Constants.Surface, lineWidth: 3)
                                }
                            }
                            .scaleEffect(
                                splitAvatarsAtCenter ? 50.0 / 107.0 : 1.0
                            )
                            .position(
                                splitAvatarsAtCenter ? clusterPos : gridPos
                            )
                            .zIndex(Double(index))
                    }
                }
                .animation(
                    .spring(response: 0.25, dampingFraction: 0.8),
                    value: isOverSplitZone
                )
                .onAppear {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8))
                    {
                        splitAvatarsAtCenter = true
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // Dragged chip overlay (on top of everything)
        .overlay {
            if let draggedItem {
                DnDBillBreakdownChip(item: draggedItem)
                    .scaleEffect(1.05)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .position(dragPosition)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "dndContainer")
        // Container size tracking
        .overlay {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ContainerSizeKey.self,
                    value: proxy.size
                )
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(ContainerSizeKey.self) { size in
            containerSize = size
        }
        .onPreferenceChange(MemberFrameKey.self) { frames in
            memberFrames = frames
        }
        .onPreferenceChange(DnDBillBreakdownCardHeightKey.self) { height in
            breakdownCardHeight = max(height, 0)
        }
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if let onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                ToolbarIconButton(
                    systemName: "checkmark",
                    foregroundColor: Constants.BlueBase
                ) {
                    onConfirm(buildConfirmData())
                }
                .disabled(memberAssignments.values.allSatisfy { $0.isEmpty })
            }
            .sharedBackgroundHiddenCompat()
        }
        .background(Constants.Background)
        .onAppear {
            for row in breakdownRows {
                for item in row {
                    remainingQuantity[item.id] = item.quantity ?? 1
                }
            }
        }
    }

    private func buildConfirmData() -> [(itemName: String, amount: Double, memberUserIds: [Int])] {
        var result: [(itemName: String, amount: Double, memberUserIds: [Int])] = []
        for (memberID, items) in memberAssignments {
            guard let member = members.first(where: { $0.id == memberID }) else { continue }
            for item in items {
                // `priceValue` is in the smallest currency unit; the server
                // expects major units (it round2s on receipt). VND
                // (decimalPlaces 0) ⇒ divisor 1, unchanged from before.
                let major =
                    Double(item.priceValue)
                    / pow(10.0, Double(currency.decimalPlaces))
                result.append((itemName: item.name, amount: major, memberUserIds: [member.userId]))
            }
        }
        return result
    }
    
    // MARK: - Split Drop Zone Indicator
    private var splitDropZoneIndicator: some View {
        let dropFrame = computedSplitDropZoneFrame

        return VStack(spacing: 10) {
            Spacer().frame(height: 50)

            Text("Drop to split evenly")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.6)
        }
        .frame(width: dropFrame.width, height: dropFrame.height)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Constants.Surface.opacity(0.9))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                )
                .foregroundStyle(
                    isOverSplitZone ? Constants.BlueBase : Constants.ContentL
                )
        }
        .scaleEffect(isOverSplitZone ? 1.05 : 1.0)
        .position(x: dropFrame.midX, y: dropFrame.midY)
        .transition(.opacity)
    }

    // MARK: - Helpers

    private func amountTag(for member: DnDBillMemberItem) -> String? {
        guard let items = memberAssignments[member.id], !items.isEmpty else {
            return nil
        }
        let total = items.reduce(0) { $0 + $1.priceValue }
        return DnDBillBreakdownItem.formatPrice(total, currency: currency)
    }

    private func splitDragOpacity(for member: DnDBillMemberItem) -> Double {
        guard isSplitDragging else { return 1.0 }
        return selectedMemberIDs.contains(member.id) ? 0.0 : 0.5
    }

    private func memberFrameCenter(for id: UUID) -> CGPoint {
        guard let frame = memberFrames[id] else { return containerCenter }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func clusterPosition(index: Int, total: Int) -> CGPoint {
        let avatarSize: CGFloat = 50
        let overlap: CGFloat = 15
        let spacing = avatarSize - overlap
        let totalWidth = avatarSize + spacing * CGFloat(total - 1)
        let startX = containerCenter.x - totalWidth / 2 + avatarSize / 2
        return CGPoint(
            x: startX + spacing * CGFloat(index),
            y: containerCenter.y
        )
    }

    // MARK: - Drag Handlers

    private func handleDragChanged(
        item: DnDBillBreakdownItem,
        position: CGPoint
    ) {
        if draggedItem?.id != item.id {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        draggedItem = item
        dragPosition = position

        if isSplitMode && !selectedMemberIDs.isEmpty {
            // Split mode: animate avatars to center, hit-test drop zone
            if !isSplitDragging {
                splitAvatarsAtCenter = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isSplitDragging = true
                }
            }
            let newOver = computedSplitDropZoneFrame.contains(position)
            if newOver != isOverSplitZone {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isOverSplitZone = newOver
                }
            }
        } else {
            // Normal mode: hit-test individual members
            let newHovered = memberFrames.first { $0.value.contains(position) }?
                .key
            if newHovered != hoveredMemberID {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    hoveredMemberID = newHovered
                }
            }
        }
    }

    private func handleDragEnded(item: DnDBillBreakdownItem) {
        let remaining = remainingQuantity[item.id, default: 0]

        if isSplitMode && isOverSplitZone && !selectedMemberIDs.isEmpty && remaining > 0 {
            // Split mode: consume 1 unit, split per-unit price evenly
            let unitPrice = item.priceValue / (item.quantity ?? 1)
            let count = selectedMemberIDs.count
            let splitAmount = unitPrice / count
            let splitRemainder = unitPrice % count
            let sortedIDs = Array(selectedMemberIDs).sorted {
                $0.uuidString < $1.uuidString
            }

            var splitMemberIDs: [UUID] = []
            var splitItemIDs: [UUID] = []

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                for (index, memberID) in sortedIDs.enumerated() {
                    let amount = splitAmount + (index < splitRemainder ? 1 : 0)
                    let splitItem = DnDBillBreakdownItem(
                        name: item.name,
                        price: DnDBillBreakdownItem.formatPrice(amount, currency: currency),
                        priceValue: amount
                    )
                    memberAssignments[memberID, default: []].append(splitItem)
                    splitMemberIDs.append(memberID)
                    splitItemIDs.append(splitItem.id)
                }
                remainingQuantity[item.id, default: 0] -= 1
            }
            assignmentHistory.append(
                .split(memberIDs: splitMemberIDs, itemIDs: splitItemIDs, sourceItemID: item.id)
            )
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if let memberID = hoveredMemberID, remaining > 0 {
            // Normal mode: consume 1 unit, assign at per-unit price
            let unitPrice = item.priceValue / (item.quantity ?? 1)
            let assignedItem = DnDBillBreakdownItem(
                name: item.name,
                price: DnDBillBreakdownItem.formatPrice(unitPrice, currency: currency),
                priceValue: unitPrice
            )
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                memberAssignments[memberID, default: []].append(assignedItem)
                remainingQuantity[item.id, default: 0] -= 1
            }
            assignmentHistory.append(
                .single(memberID: memberID, itemID: assignedItem.id, sourceItemID: item.id)
            )
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }

        draggedItem = nil
        hoveredMemberID = nil
        isOverSplitZone = false

        if isSplitDragging {
            // Animate avatars back to grid positions, then hide overlay
            withAnimation(
                .spring(response: 0.4, dampingFraction: 0.8),
                completionCriteria: .logicallyComplete
            ) {
                splitAvatarsAtCenter = false
            } completion: {
                withAnimation(.smooth(duration: 0.2)) {
                    isSplitDragging = false
                }
            }
        }
    }

    private func performUndo() {
        guard let lastAction = assignmentHistory.popLast() else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switch lastAction {
            case .single(let memberID, let itemID, let sourceItemID):
                memberAssignments[memberID]?.removeAll { $0.id == itemID }
                remainingQuantity[sourceItemID, default: 0] += 1
            case .split(let memberIDs, let itemIDs, let sourceItemID):
                for (memberID, itemID) in zip(memberIDs, itemIDs) {
                    memberAssignments[memberID]?.removeAll { $0.id == itemID }
                }
                remainingQuantity[sourceItemID, default: 0] += 1
            }
        }
    }

    private func performReset() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            memberAssignments.removeAll()
            assignmentHistory.removeAll()
            for row in breakdownRows {
                for item in row {
                    remainingQuantity[item.id] = item.quantity ?? 1
                }
            }
        }
    }
}

enum AssignmentAction {
    case single(memberID: UUID, itemID: UUID, sourceItemID: UUID)
    case split(memberIDs: [UUID], itemIDs: [UUID], sourceItemID: UUID)
}

// MARK: - Preference Keys

private struct DnDBillBreakdownCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct MemberFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(
        value: inout [UUID: CGRect],
        nextValue: () -> [UUID: CGRect]
    ) {
        value.merge(nextValue()) { $1 }
    }
}

private struct ContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Models

struct DnDBillMemberItem: Identifiable {
    let id = UUID()
    let userId: Int
    let name: String
    let imageURL: String
}

struct DnDBillBreakdownItem: Identifiable {
    let id = UUID()
    let name: String
    let quantity: Int?
    let price: String
    let priceValue: Int

    init(name: String, quantity: Int? = nil, price: String, priceValue: Int) {
        self.name = name
        self.quantity = quantity
        self.price = price
        self.priceValue = priceValue
    }

    /// `value` is in the smallest currency unit (the receipt-scan API
    /// returns satang/cents/dong). Convert to major units for display and
    /// reuse the canonical decimal-aware formatter (symbol-first, used by
    /// `ExpenseDetailView` etc.). VND (decimalPlaces 0) ⇒ divisor 1.
    static func formatPrice(_ value: Int, currency: Currency = .VND) -> String {
        let major =
            Double(value) / pow(10.0, Double(currency.decimalPlaces))
        return CurrencyFormatter.format(major, currency: currency)
    }
}

// MARK: - Avatar Image (shared between grid and overlay)

struct DnDBillAvatarImage: View {
    let imageURL: String

    var body: some View {
        if let url = URL(string: imageURL) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image("avatarPlaceholder").resizable().scaledToFill()
            }
        } else {
            Image("avatarPlaceholder").resizable().scaledToFill()
        }
    }
}

// MARK: - Member Cell

struct DnDBillMemberCell: View {
    let member: DnDBillMemberItem
    var isHovered: Bool = false
    var amountTag: String? = nil
    var showCheckbox: Bool = false
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 5.585) {
            DnDBillAvatarImage(imageURL: member.imageURL)
                .frame(width: 107, height: 107)
                .clipShape(
                    RoundedRectangle(cornerRadius: 33.513, style: .continuous)
                )
                .overlay(alignment: .bottomTrailing) {
                    if showCheckbox {
                        ZStack {
                            Circle()
                                .fill(
                                    isSelected
                                        ? Constants.BlueBase : Constants.Surface
                                )

                            Circle()
                                .stroke(
                                    isSelected
                                        ? Constants.BlueBase
                                        : Constants.ContentL,
                                    lineWidth: 1.5
                                )

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Constants.White)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .offset(x: 4, y: 4)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    if isHovered {
                        RoundedRectangle(
                            cornerRadius: .infinity,
                            style: .continuous
                        )
                        .stroke(Constants.BlueBase, lineWidth: 2.5)
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let amountTag {
                        Text(amountTag)
                            .font(
                                Font.custom("SF Compact Rounded", size: 12)
                                    .weight(.medium)
                            )
                            .foregroundStyle(Constants.White)
                            .tracking(-0.6)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Constants.BlueBase)
                            .clipShape(Capsule())
                            .offset(x: 25, y: -8)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(
                    .spring(response: 0.25, dampingFraction: 0.8),
                    value: isHovered
                )

            Text(member.name)
                .font(Font.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.ContentM)
                .lineLimit(1)
                .frame(width: 58.089)
                .multilineTextAlignment(.center)
        }
        .frame(width: 107)
    }
}

// MARK: - Breakdown Card

struct DnDBillBreakdownCard: View {
    @Binding var title: String
    let rows: [[DnDBillBreakdownItem]]
    var remainingQuantity: [UUID: Int] = [:]
    var draggedItemID: UUID? = nil
    var isSplitMode: Bool = false
    var onToggleSplit: (() -> Void)? = nil
    var hasUndoHistory: Bool = false
    var onUndo: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil
    var onDragChanged: ((DnDBillBreakdownItem, CGPoint) -> Void)? = nil
    var onDragEnded: ((DnDBillBreakdownItem) -> Void)? = nil

    @State private var isLongPressing: Bool = false
    @State private var pressStartTime: Date? = nil
    @State private var resetCountdown: CGFloat = 0
    @State private var showResetCapsule: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Restaurant name", text: $title)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.6)
                    .lineLimit(1)

                Spacer(minLength: 0)

                // Undo button with long-press Reset
                undoButton

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggleSplit?()
                } label: {
                    Text("Split")
                        .font(
                            Font.beVietnamPro(14, weight: .medium)
                        )
                        .foregroundStyle(
                            isSplitMode ? Constants.White : Constants.ContentM
                        )
                        .tracking(-0.6)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            isSplitMode ? Constants.BlueBase : Color.clear
                        )
                        .clipShape(Capsule())
                        .overlay {
                            if !isSplitMode {
                                Capsule()
                                    .stroke(Constants.ContentL, lineWidth: 1)
                            }
                        }
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 4) {
                        ForEach(row) { item in
                            let remaining = remainingQuantity[item.id, default: 0]
                            let isExhausted = remaining <= 0

                            DnDBillBreakdownChip(
                                item: item,
                                remainingQuantity: remaining,
                                isDimmed: draggedItemID == item.id,
                                isExhausted: isExhausted
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .gesture(
                                isExhausted ? nil :
                                DragGesture(
                                    minimumDistance: 5,
                                    coordinateSpace: .named("dndContainer")
                                )
                                .onChanged { value in
                                    onDragChanged?(item, value.location)
                                }
                                .onEnded { _ in
                                    onDragEnded?(item)
                                }
                            )
                        }
                    }
                }
            }
            .padding(4)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if showResetCapsule {
                resetCapsule
                    .padding(.trailing, 8)
                    .offset(x: -45, y: -35)
                    .transition(
                        .scale(scale: 0.6, anchor: .bottom).combined(
                            with: .opacity
                        )
                    )
            }
        }
    }

    // MARK: - Undo Button

    private var undoButton: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 11, weight: .semibold))
            Text("Undo")
                .font(
                    Font.beVietnamPro(14, weight: .medium)
                )
                .tracking(-0.6)
        }
        .foregroundStyle(hasUndoHistory ? Constants.White : Constants.ContentM)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(hasUndoHistory ? Constants.BlueBase : Color.clear)
        .clipShape(Capsule())
        .overlay {
            if !hasUndoHistory {
                Capsule()
                    .stroke(Constants.ContentL, lineWidth: 1)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isLongPressing {
                        pressStartTime = Date()
                        isLongPressing = true
                    }
                }
                .onEnded { _ in
                    let wasTap =
                        pressStartTime.map {
                            Date().timeIntervalSince($0) < 0.3
                        } ?? false
                    isLongPressing = false
                    pressStartTime = nil
                    if wasTap {
                        if hasUndoHistory {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                        onUndo?()
                    }
                }
        )
        .task(id: isLongPressing) {
            guard isLongPressing else {
                // Released — cancel and clean up
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    showResetCapsule = false
                }
                withAnimation(.easeOut(duration: 0.15)) {
                    resetCountdown = 0
                }
                return
            }

            // Phase 1: Hold for 1 second
            do {
                try await Task.sleep(for: .seconds(1))
            } catch { return }

            // Phase 2: Show Reset capsule, start 2s countdown
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showResetCapsule = true
            }
            withAnimation(.linear(duration: 2.0)) {
                resetCountdown = 1.0
            }

            // Phase 3: Wait for countdown to finish
            do {
                try await Task.sleep(for: .seconds(2))
            } catch { return }

            // Phase 4: Countdown complete — trigger reset
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onReset?()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                showResetCapsule = false
                resetCountdown = 0
            }
        }
    }

    private var resetCapsule: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Constants.ContentL.opacity(0.3), lineWidth: 2)

                Circle()
                    .trim(from: 0, to: resetCountdown)
                    .stroke(
                        Constants.BlueBase,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Constants.ContentB)
            }
            .frame(width: 20, height: 20)

            Text("Reset")
                .font(
                    Font.beVietnamPro(14, weight: .medium)
                )
                .foregroundStyle(Constants.ContentB)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(Constants.Surface)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        }
        .overlay {
            GeometryReader { proxy in
                Capsule()
                    .fill(Constants.BlueBase.opacity(0.08))
                    .frame(width: proxy.size.width * resetCountdown)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(Capsule())
        }
        .overlay {
            Capsule()
                .stroke(Constants.ContentL.opacity(0.3), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Breakdown Chip

struct DnDBillBreakdownChip: View {
    let item: DnDBillBreakdownItem
    var remainingQuantity: Int = 1
    var isDimmed: Bool = false
    var isExhausted: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                Text(item.name)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.ContentB)
                    .tracking(-0.7)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if remainingQuantity > 1 || (item.quantity != nil && remainingQuantity > 0) {
                    ZStack {
                        Circle()
                            .fill(Constants.BlueAlpha16)

                        Text("\(remainingQuantity)")
                            .font(
                                Font.beVietnamPro(9.6, weight: .semibold)
                            )
                            .foregroundStyle(Constants.BlueBase)
                    }
                    .frame(width: 16, height: 16)
                }
            }

            Text(item.price)
                .font(
                    Font.custom("SF Compact Rounded", size: 14).weight(.medium)
                )
                .foregroundStyle(Constants.BlueBase)
                .tracking(-0.7)
                .lineLimit(1)
                .layoutPriority(1)
        }
        .padding(10)
        .background(Constants.BlueAlpha10)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isExhausted ? 0.3 : (isDimmed ? 0.3 : 1.0))
        .animation(.easeOut(duration: 0.2), value: isDimmed)
        .animation(.easeOut(duration: 0.2), value: isExhausted)
    }
}

#Preview {
    DnDBillItemsView(
        members: [
            DnDBillMemberItem(userId: 1, name: "Alice", imageURL: ""),
            DnDBillMemberItem(userId: 2, name: "Bob", imageURL: ""),
            DnDBillMemberItem(userId: 3, name: "Charlie", imageURL: ""),
        ],
        breakdownRows: [
            [
                DnDBillBreakdownItem(name: "Chicken rice", quantity: 2, price: "50,000đ", priceValue: 50_000),
                DnDBillBreakdownItem(name: "Americano", price: "45,000đ", priceValue: 45_000),
            ],
            [
                DnDBillBreakdownItem(name: "Ramen Noodles", price: "65,000đ", priceValue: 65_000),
                DnDBillBreakdownItem(name: "Tea", price: "8,000đ", priceValue: 8_000),
            ],
        ],
        restaurantName: .constant("Mi Cay Sasin")
    )
}
