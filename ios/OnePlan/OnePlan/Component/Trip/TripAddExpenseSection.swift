//
//  TripAddExpenseSection.swift
//  OnePlan
//
//  Created by Codex on 20/3/26.
//

import SwiftUI

struct TripAddExpenseSection: View {
    let members: [TripMemberDto]
    var onCategoryChanged: ((CategoryChip.Category) -> Void)?
    var onMembersChanged: (([Int]) -> Void)?

    @State private var selectedCategory: CategoryChip.Category = .food
    @State private var isAllSelected: Bool = true
    @State private var selectedMemberIds: Set<Int> = []

    private let categories: [CategoryChip.Category] = [
        .food, .stay, .ticket, .transport, .other,
    ]
    private var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }
    private var acceptedMemberIds: [Int] {
        acceptedMembers.map { Int($0.userId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            categorySection
            shareWithSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: selectedCategory) { _, newCategory in
            onCategoryChanged?(newCategory)
        }
        .onChange(of: isAllSelected) { _, newValue in
            if newValue {
                onMembersChanged?(acceptedMemberIds)
            }
        }
        .onChange(of: selectedMemberIds) { _, newIds in
            if newIds.isEmpty && !isAllSelected {
                // Auto-select "All" when last member is deselected
                isAllSelected = true
                selectedMemberIds.removeAll()
            } else if !isAllSelected {
                onMembersChanged?(Array(newIds))
            }
        }
        .onAppear {
            // Default to all members selected
            onCategoryChanged?(selectedCategory)
            onMembersChanged?(acceptedMemberIds)
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Category")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(categories, id: \.title) { category in
                        Button {
                            selectedCategory = category
                        } label: {
                            CategoryChip(
                                category: category,
                                isSelected: selectedCategory == category
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }

    private var shareWithSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share with")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .lineLimit(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    TripShareWithAllChip(isSelected: isAllSelected) {
                        isAllSelected = true
                        selectedMemberIds.removeAll()
                    }

                    ForEach(acceptedMembers, id: \.id) { member in
                        let memberId = Int(member.userId)
                        TripShareWithMemberChip(
                            name: member.displayName,
                            avatarUrl: member.avatarUrl,
                            isSelected: selectedMemberIds.contains(memberId)
                        ) {
                            if isAllSelected {
                                isAllSelected = false
                            }
                            if selectedMemberIds.contains(memberId) {
                                selectedMemberIds.remove(memberId)
                            } else {
                                selectedMemberIds.insert(memberId)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.top, 8)
    }
}

private struct TripShareWithAllChip: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Constants.Black)
                        .frame(width: 32, height: 32)

                    Image(systemName: "person.3.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Constants.White)
                }
                .frame(width: 36, height: 36)
                .overlay {
                    Circle()
                        .stroke(
                            isSelected ? Constants.BlueBase : Color.clear,
                            lineWidth: 2
                        )
                }

                Text("All")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(isSelected ? Constants.BlueBase : Constants.ContentM)
                    .lineLimit(1)
                    .frame(width: 52)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct TripShareWithMemberChip: View {
    let name: String
    let avatarUrl: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                avatar
                    .frame(width: 36, height: 36)
                    .overlay {
                        Circle()
                            .stroke(
                                isSelected ? Constants.BlueBase : Color.clear,
                                lineWidth: 2
                            )
                    }

                Text(name)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(isSelected ? Constants.BlueBase : Constants.ContentM)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 52)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarUrl, let url = URL(string: avatarUrl) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(Circle())
        } else {
            Image("defaultTripPlaceholder")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        }
    }
}

#Preview {
    TripAddExpenseSection(members: [])
        .padding()
        .background(Constants.Background)
}
