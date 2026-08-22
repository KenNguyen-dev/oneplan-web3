import SwiftUI

/// What a vault payment is recorded as once it succeeds.
struct VaultExpenseDetails {
    var name: String
    var category: CategoryChip.Category
    /// Empty means everyone shares.
    var shareWithUserIds: [Int]
}

// There is no payer to choose. A vault payment comes out of the group's money,
// so the group is always the payer, and the receipt reports the member who
// initiated it as "made by" instead. Offering a picker would only let someone
// record something the chain contradicts.

/// Collects the expense side of a vault payment: what it was, who paid, who
/// splits it.
///
/// Shown before the money moves, not after, so the trip ledger is never left
/// holding an unexplained transfer.
struct VaultExpenseSheet: View {
    let members: [TripMemberDto]
    /// Used when the name is left blank: a payment always knows who it pays, so
    /// there is no reason to block on typing that in again.
    var fallbackName: String = ""
    var onDone: (VaultExpenseDetails) -> Void

    @State private var name = ""
    @State private var category: CategoryChip.Category = .coffee
    @State private var isSharedWithAll = true
    @State private var shareWithUserIds: Set<Int> = []
    @State private var isShowingCategories = false

    private var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Constants.Neutral200)
                .frame(width: 35, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)

            Text("Add new expenses")
                .font(Font.beVietnamPro(18))
                .tracking(-0.36)
                .foregroundStyle(Constants.ContentB)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

            categoryAndName
                .padding(.top, 16)


            memberRow(
                title: "Share with",
                leadingLabel: "All",
                isLeadingSelected: isSharedWithAll,
                tint: Constants.BlueBase,
                isSelected: { !isSharedWithAll && shareWithUserIds.contains($0) },
                onLeadingTapped: {
                    isSharedWithAll = true
                    shareWithUserIds.removeAll()
                },
                onMemberTapped: { toggleShare($0) }
            )
            .padding(.top, 16)

            Spacer(minLength: 16)

            Button {
                onDone(
                    VaultExpenseDetails(
                        name: resolvedName,
                        category: category,
                        shareWithUserIds: resolvedShareWithUserIds
                    )
                )
            } label: {
                Text("Done")
                    .font(Font.beVietnamPro(17))
                    .tracking(-0.68)
                    .foregroundStyle(Constants.White)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(VaultPalette.accent, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Surface)
        .sheet(isPresented: $isShowingCategories) {
            CategoryPickerSheet(selected: $category) {
                isShowingCategories = false
            }
            .presentationDetents([.large])
        }
    }

    /// Blank falls back to who was paid. Blocking on a name would stop a
    /// payment the user has already decided to make, over a label the receipt
    /// can supply.
    private var resolvedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return fallbackName.isEmpty ? category.title : fallbackName
    }

    /// The server treats an empty list as "everyone", which is also what the
    /// All chip means. Sending every id instead made history render faces
    /// instead of the All chip.
    private var resolvedShareWithUserIds: [Int] {
        isSharedWithAll ? [] : Array(shareWithUserIds)
    }

    /// A 92pt category chip and the name field beside it, both 59pt tall.
    private var categoryAndName: some View {
        HStack(spacing: 8) {
            Button {
                isShowingCategories = true
            } label: {
                HStack(spacing: 5) {
                    CategoryIcon(category: category, size: 43)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Constants.ContentM)
                }
                .frame(width: 92, height: 59)
                .background(
                    Constants.Background,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Category, \(category.title)")

            TextField("Transaction name", text: $name)
                .font(Font.beVietnamPro(16))
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 59)
                .background(
                    Constants.Background,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
        }
    }

    /// Cells are 52pt wide holding a 36pt avatar and a 17pt label, 14pt apart.
    private func memberRow(
        title: LocalizedStringKey,
        leadingLabel: String,
        isLeadingSelected: Bool,
        tint: Color,
        isSelected: @escaping (Int) -> Bool,
        onLeadingTapped: @escaping () -> Void,
        onMemberTapped: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Font.beVietnamPro(14))
                .foregroundStyle(Constants.ContentM)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    MemberSelectChip(
                        name: leadingLabel,
                        avatarUrl: nil,
                        systemImage: "person.3.fill",
                        isSelected: isLeadingSelected,
                        tint: tint,
                        action: onLeadingTapped
                    )

                    ForEach(acceptedMembers, id: \.id) { member in
                        MemberSelectChip(
                            name: member.displayName,
                            avatarUrl: member.avatarUrl,
                            isSelected: isSelected(Int(member.userId)),
                            tint: tint,
                            action: { onMemberTapped(Int(member.userId)) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func toggleShare(_ userId: Int) {
        isSharedWithAll = false
        if shareWithUserIds.contains(userId) {
            shareWithUserIds.remove(userId)
        } else {
            shareWithUserIds.insert(userId)
        }
        // Deselecting the last member would mean nobody shares the expense,
        // which is not a state the ledger can represent.
        if shareWithUserIds.isEmpty {
            isSharedWithAll = true
        }
    }
}
