import SwiftUI

/// Edits vault spend metadata after the money has already moved.
///
/// Amount is locked: the on-chain transfer already happened. Only the ledger
/// label (name), category, and share split can change.
/// Figma `4575:14996`.
struct VaultTransactionEditView: View {
    let tripId: Int
    let vaultTransactionId: Int
    let amountVnd: UInt64
    /// VND per USDC — used only for the read-only `$x.xx` line under the amount.
    let rate: UInt64
    let members: [TripMemberDto]
    let initialName: String
    let initialCategory: CategoryChip.Category
    /// Empty means shared with everyone.
    let initialShareWithUserIds: [Int]
    var onBack: () -> Void = {}
    /// DTO plus the name just written (Client may lag the `name` field).
    var onSaved: (Components.Schemas.VaultTransactionDetailDto, String) -> Void

    @State private var name: String
    @State private var category: CategoryChip.Category
    @State private var isSharedWithAll: Bool
    @State private var shareWithUserIds: Set<Int>
    @State private var isShowingCategories = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    @State private var vault = TripVaultService.shared

    init(
        tripId: Int,
        vaultTransactionId: Int,
        amountVnd: UInt64,
        rate: UInt64 = 0,
        members: [TripMemberDto],
        initialName: String,
        initialCategory: CategoryChip.Category,
        initialShareWithUserIds: [Int],
        onBack: @escaping () -> Void = {},
        onSaved: @escaping (Components.Schemas.VaultTransactionDetailDto, String) -> Void
    ) {
        self.tripId = tripId
        self.vaultTransactionId = vaultTransactionId
        self.amountVnd = amountVnd
        self.rate = rate
        self.members = members
        self.initialName = initialName
        self.initialCategory = initialCategory
        self.initialShareWithUserIds = initialShareWithUserIds
        self.onBack = onBack
        self.onSaved = onSaved

        _name = State(initialValue: initialName)
        _category = State(initialValue: initialCategory)
        let sharedWithAll = initialShareWithUserIds.isEmpty
        _isSharedWithAll = State(initialValue: sharedWithAll)
        _shareWithUserIds = State(initialValue: Set(initialShareWithUserIds))
    }

    private var acceptedMembers: [TripMemberDto] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }
    }

    private var usdcText: String {
        guard rate > 0 else { return "" }
        return String(format: "$%.2f", Double(amountVnd) / Double(rate))
    }

    var body: some View {
        VStack(spacing: 0) {
            TripEndConsensusChrome.BackHeader(onBack: onBack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    amountBlock
                        .padding(.top, 48)
                        .padding(.bottom, 28)

                    categoryAndName
                        .padding(.bottom, 16)

                    memberRow(
                        title: "Share with",
                        leadingLabel: String(localized: "All"),
                        isLeadingSelected: isSharedWithAll,
                        tint: Constants.BlueBase,
                        isSelected: { !isSharedWithAll && shareWithUserIds.contains($0) },
                        onLeadingTapped: {
                            isSharedWithAll = true
                            shareWithUserIds.removeAll()
                        },
                        onMemberTapped: { toggleShare($0) }
                    )
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }

            Button {
                Task { await save() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(Constants.White)
                    } else {
                        Text("Done")
                            .font(Font.beVietnamPro(17))
                            .tracking(-0.68)
                            .foregroundStyle(Constants.White)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
            .glassEffectCompat(
                in: Capsule(),
                interactive: true,
                tint: VaultPalette.accent
            )
            .disabled(isSaving)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Constants.Background)
        .sheet(isPresented: $isShowingCategories) {
            CategoryPickerSheet(selected: $category) {
                isShowingCategories = false
            }
            .presentationDetents([.large])
        }
        .alert(
            "Could not save",
            isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(errorMessage ?? "") }
        )
    }

    /// Read-only. Changing it would disagree with the on-chain transfer.
    private var amountBlock: some View {
        VStack(spacing: 16) {
            Text("VND")
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Constants.Neutral900)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .vaultHeaderChip()

            Text(CurrencyFormatter.formatWhole(Double(amountVnd)))
                .font(Font.beVietnamPro(48))
                .tracking(-2.4)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            if !usdcText.isEmpty {
                Text(usdcText)
                    .font(Font.beVietnamPro(14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.Neutral600)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Amount \(CurrencyFormatter.formatWhole(Double(amountVnd))) dong, about \(usdcText). Amount cannot be edited."
        )
    }

    private var categoryAndName: some View {
        HStack(spacing: 8) {
            Button {
                isShowingCategories = true
            } label: {
                HStack(spacing: 5) {
                    CategoryIcon(category: category, size: 43)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Constants.ContentM)
                        .frame(width: 12, height: 7)
                }
                .padding(.leading, 12)
                .padding(.trailing, 20)
                .padding(.vertical, 8)
                .background(
                    Constants.White,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Category, \(category.title)")

            TextField("Transaction name", text: $name)
                .font(Font.beVietnamPro(16))
                .tracking(-0.32)
                .foregroundStyle(Constants.ContentB)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, minHeight: 59, alignment: .leading)
                .background(
                    Constants.White,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
        }
    }

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
                .font(Font.beVietnamPro(16, weight: .medium))
                .tracking(-0.32)
                .foregroundStyle(Constants.Neutral600)

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
        if shareWithUserIds.isEmpty {
            isSharedWithAll = true
        }
    }

    private var resolvedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? category.title : typed
    }

    private var resolvedShareWithUserIds: [Int] {
        isSharedWithAll ? [] : Array(shareWithUserIds)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let categoryApi =
                Components.Schemas.ExpenseCategory(rawValue: category.apiValue) ?? .OTHER
            let savedName = resolvedName
            let updated = try await vault.updateVaultSpend(
                tripId: tripId,
                vaultTransactionId: vaultTransactionId,
                name: savedName,
                category: categoryApi,
                shareWithUserIds: resolvedShareWithUserIds
            )
            onSaved(updated, savedName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
