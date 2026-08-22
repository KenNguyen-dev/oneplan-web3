import SwiftUI

/// Everything the app knows about one vault payment.
///
/// Deliberately a plain value rather than a generated DTO: the server has no
/// endpoint returning this yet, so pinning the shape here says exactly what that
/// endpoint has to provide.
struct VaultTransactionDetail: Equatable {
    enum Status: Equatable {
        case completed
        case pending
        case failed
    }

    var amountVnd: UInt64
    var recipientName: String
    var status: Status
    var date: Date
    var bankName: String
    var bankAccountNumber: String
    /// Fee in VND, with the percentage it represents shown beside it.
    var feeVnd: UInt64
    var feePercent: Double
    /// Fee in USDC (for the "$x paid for one time payment" footer).
    var feeUsdc: Double
    /// VND per USDC at the time the payment was priced.
    var rate: UInt64
    var note: String?
    /// Expense / TX display name. Separate from the bank transfer note.
    var name: String

    /// True while the payment is above the trip limit and no second member has
    /// approved it. The money has not moved.
    var needsApproval: Bool = false
    /// Whether this viewer may add the second signature. Answered by the server,
    /// which alone knows how many approvers the trip has named.
    var canApprove: Bool = false
    /// Whether this viewer may cancel the open proposal (proposer or host).
    var canCancel: Bool = false
    /// Whether this viewer may edit name / category / share (payer or host).
    var canEdit: Bool = false

    var category: CategoryChip.Category
    /// Nil when the group paid rather than one member.
    var paidByName: String?
    /// Nil when everyone shares.
    var shareWithNames: [String]?
    /// Empty means shared with everyone. Used to prefill the edit screen.
    var shareWithUserIds: [Int]
    var madeByName: String
    var madeByAvatarUrl: String?
    /// The code this paid, so it can be paid again without scanning.
    var qrPayload: String?
}

/// The receipt for a single vault payment.
/// Figma `4575:15159`.
struct VaultTransactionDetailView: View {
    @State private var detail: VaultTransactionDetail
    /// Required together to offer "Edit details" on a confirmed spend.
    var tripId: Int? = nil
    var vaultTransactionId: Int? = nil
    var members: [TripMemberDto] = []
    /// False after the trip has ended — server rejects edits then.
    var allowsEditing: Bool = true
    var onBack: () -> Void = {}
    var onSendAgain: (() -> Void)?
    /// Absent when this payment is not waiting on the viewer.
    var onApprove: (() async -> Void)?
    /// Absent when this viewer cannot cancel the open proposal.
    var onCancel: (() async -> Void)?
    /// Fired after a successful metadata edit so the parent can refresh.
    var onEdited: ((Components.Schemas.VaultTransactionDetailDto, String) -> Void)?

    @State private var isApproving = false
    @State private var isCancelling = false
    @State private var confirmCancel = false
    @State private var isEditing = false

    private let shellFill = Color(red: 0.937, green: 0.937, blue: 0.937)
    private let valueInk = Color(red: 0.224, green: 0.224, blue: 0.224)

    init(
        detail: VaultTransactionDetail,
        tripId: Int? = nil,
        vaultTransactionId: Int? = nil,
        members: [TripMemberDto] = [],
        allowsEditing: Bool = true,
        onBack: @escaping () -> Void = {},
        onSendAgain: (() -> Void)? = nil,
        onApprove: (() async -> Void)? = nil,
        onCancel: (() async -> Void)? = nil,
        onEdited: ((Components.Schemas.VaultTransactionDetailDto, String) -> Void)? = nil
    ) {
        _detail = State(initialValue: detail)
        self.tripId = tripId
        self.vaultTransactionId = vaultTransactionId
        self.members = members
        self.allowsEditing = allowsEditing
        self.onBack = onBack
        self.onSendAgain = onSendAgain
        self.onApprove = onApprove
        self.onCancel = onCancel
        self.onEdited = onEdited
    }

    /// Offered only to someone the chain will accept. A member who raised the
    /// payment cannot sign it twice, and on a trip that has named its approvers
    /// nobody else may sign at all — a button that fails is worse than none.
    private var showsApprove: Bool {
        detail.canApprove && onApprove != nil
    }

    private var showsCancel: Bool {
        detail.canCancel && onCancel != nil
    }

    private var showsEdit: Bool {
        allowsEditing
            && detail.canEdit
            && detail.status == .completed
            && tripId != nil
            && vaultTransactionId != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 20) {
                    hero
                        .padding(.top, 28)

                    detailsShell
                        .padding(.horizontal, 7)
                }
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .top) {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.706, green: 0.875, blue: 1), location: 0),
                    .init(color: Color(red: 0.984, green: 0.925, blue: 0.843), location: 0.514),
                    .init(color: Constants.Background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 312)
            .frame(maxWidth: .infinity)
            .ignoresSafeArea(edges: .top)
        }
        .background(Constants.Background)
        .alert("Cancel this payment?", isPresented: $confirmCancel) {
            Button("Keep waiting", role: .cancel) {}
            Button("Cancel payment", role: .destructive) {
                guard let onCancel else { return }
                isCancelling = true
                Task {
                    await onCancel()
                    isCancelling = false
                }
            }
        } message: {
            Text("The proposal will be dropped. No money moves.")
        }
        .fullScreenCover(isPresented: $isEditing) {
            if let tripId, let vaultTransactionId {
                VaultTransactionEditView(
                    tripId: tripId,
                    vaultTransactionId: vaultTransactionId,
                    amountVnd: detail.amountVnd,
                    rate: detail.rate,
                    members: members,
                    initialName: detail.name,
                    initialCategory: detail.category,
                    initialShareWithUserIds: detail.shareWithUserIds,
                    onBack: { isEditing = false },
                    onSaved: { updated, savedName in
                        detail = Self.map(updated, fallbackName: savedName)
                        isEditing = false
                        onEdited?(updated, savedName)
                    }
                )
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("Transaction details")
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.ContentB)

            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Constants.Neutral900)
                        .frame(width: 32, height: 32)
                }
                .vaultHeaderChip()
                .accessibilityLabel("Back")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private var hero: some View {
        VStack(spacing: 20) {
            Text(amountText)
                .font(Font.beVietnamPro(48))
                .tracking(-2.4)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            (Text("Transfer to ").foregroundColor(Constants.Neutral600)
                + Text(detail.recipientName).foregroundColor(Constants.ContentB))
                .font(Font.beVietnamPro(18))
                .tracking(-0.36)

            if showsApprove {
                Button {
                    guard let onApprove else { return }
                    isApproving = true
                    Task {
                        await onApprove()
                        isApproving = false
                    }
                } label: {
                    Group {
                        if isApproving {
                            ProgressView().tint(Constants.White)
                        } else {
                            Text("Approve payment")
                                .font(Font.beVietnamPro(15))
                                .tracking(-0.75)
                                .foregroundStyle(Constants.White)
                        }
                    }
                    .frame(width: 180, height: 44)
                    .background(VaultPalette.accent, in: Capsule())
                }
                .disabled(isApproving || isCancelling)
            } else if detail.needsApproval {
                Text("Waiting for another member to approve")
                    .font(Font.beVietnamPro(14))
                    .foregroundStyle(Constants.Warning500)
            }

            if showsCancel {
                Button {
                    confirmCancel = true
                } label: {
                    Group {
                        if isCancelling {
                            ProgressView().tint(Constants.Secondary)
                        } else {
                            Text("Cancel payment")
                                .font(Font.beVietnamPro(15))
                                .foregroundStyle(Constants.Secondary)
                        }
                    }
                    .frame(minWidth: 147, minHeight: 44)
                }
                .disabled(isApproving || isCancelling)
            }

            if let onSendAgain {
                Button(action: onSendAgain) {
                    Text("Send again")
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.75)
                        .foregroundStyle(Constants.ContentB)
                        .frame(width: 147, height: 44)
                }
                .glassEffectCompat(in: Capsule(), interactive: false)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var detailsShell: some View {
        VStack(spacing: 16) {
            paymentCard
            groupDetailsBlock
            if detail.feeUsdc > 0 {
                Text(
                    "\(String(format: "$%.2f", detail.feeUsdc)) paid for one time payment"
                )
                .font(Font.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(valueInk)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .background(shellFill, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var paymentCard: some View {
        VStack(spacing: 16) {
            row("Status") {
                HStack(spacing: 5) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 16))
                        .foregroundStyle(statusColor)
                        .frame(width: 19, height: 19)
                    Text(statusTitle)
                        .font(Font.beVietnamPro(16))
                        .tracking(-0.32)
                        .foregroundStyle(valueInk)
                }
            }
            row("Date") { valueText(Self.dateFormatter.string(from: detail.date)) }
            row("Bank name") { valueText(detail.bankName) }
            row("Bank account number") { valueText(detail.bankAccountNumber) }
            row("Recipient name") { valueText(detail.recipientName) }
            row(feeLabel) {
                valueText(
                    CurrencyFormatter.formatWhole(Double(detail.feeVnd))
                        + Currency.VND.symbol
                )
            }
            // USDC, not USDT: the vault holds USDC, and the design's "1USDT"
            // label is a placeholder.
            row("Rate") {
                valueText(
                    "1 USDC = "
                        + CurrencyFormatter.formatWhole(Double(detail.rate))
                        + Currency.VND.symbol
                )
            }

            if let note = detail.note, !note.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .font(Font.beVietnamPro(15))
                        .tracking(-0.45)
                        .foregroundStyle(Constants.ContentM)
                    Text(note)
                        .font(Font.beVietnamPro(16, weight: .medium))
                        .tracking(-0.32)
                        .foregroundStyle(valueInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Constants.White)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var groupDetailsBlock: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Group details")
                    .font(Font.beVietnamPro(16))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)
                Spacer(minLength: 8)
                if showsEdit {
                    Button {
                        isEditing = true
                    } label: {
                        Text("Edit details")
                            .font(Font.beVietnamPro(14))
                            .tracking(-0.28)
                            .foregroundStyle(Constants.Background)
                            .padding(.horizontal, 8)
                            .padding(.top, 2)
                            .padding(.bottom, 3)
                            .background(Constants.Neutral900, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 16) {
                row("Share with") {
                    pill(shareWithLabel, tint: Constants.BlueBase)
                }
                row("Category") {
                    HStack(spacing: 5) {
                        CategoryIcon(category: detail.category, size: 24)
                        valueText(detail.category.title)
                    }
                }
                row("Created by") {
                    HStack(spacing: 5) {
                        avatar
                        valueText(detail.madeByName)
                    }
                }
            }
            .padding(16)
            .background(Constants.White)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    // MARK: - Pieces

    private var amountText: String {
        CurrencyFormatter.formatWhole(Double(detail.amountVnd)) + Currency.VND.symbol
    }

    private func row<Value: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(Font.beVietnamPro(15))
                .tracking(-0.45)
                .foregroundStyle(Constants.ContentM)
            Spacer(minLength: 0)
            value()
        }
    }

    private func valueText(_ text: String) -> some View {
        Text(text)
            .font(Font.beVietnamPro(16))
            .tracking(-0.32)
            .foregroundStyle(valueInk)
            .multilineTextAlignment(.trailing)
    }

    private func pill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(Font.beVietnamPro(14))
            .tracking(-0.28)
            .foregroundStyle(Constants.Background)
            .padding(.horizontal, 8)
            .padding(.top, 2)
            .padding(.bottom, 3)
            .background(tint, in: Capsule())
    }

    @ViewBuilder
    private var avatar: some View {
        if let url = detail.madeByAvatarUrl.flatMap(URL.init(string:)) {
            CachedRemoteImage(url: url, targetSize: CGSize(width: 19, height: 19)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { initialsAvatar }
            .frame(width: 19, height: 19)
            .clipShape(Circle())
        } else {
            initialsAvatar.frame(width: 19, height: 19)
        }
    }

    /// Shown when there is no picture. An empty disc names nobody, which is the
    /// one job the avatar has here.
    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(Constants.Neutral200)
            Text(String(detail.madeByName.prefix(1)).uppercased())
                .font(Font.beVietnamPro(10))
                .foregroundStyle(Constants.ContentM)
        }
    }

    private var feeLabel: LocalizedStringKey {
        // Trimmed rather than fixed to one place: 0.75 must not print as 0.7,
        // and 1.0 should not print as 1.00.
        let text = String(format: "%.2f", detail.feePercent)
            .replacingOccurrences(of: #"0$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[.]$"#, with: "", options: .regularExpression)
        return "Fee (\(text)%)"
    }

    private var shareWithLabel: String {
        guard let names = detail.shareWithNames, !names.isEmpty else {
            return String(localized: "All")
        }
        return names.count == 1 ? names[0] : "\(names.count) people"
    }

    private var statusTitle: LocalizedStringKey {
        switch detail.status {
        case .completed: "Completed"
        case .pending: "Processing"
        case .failed: "Failed"
        }
    }

    private var statusIcon: String {
        switch detail.status {
        case .completed: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch detail.status {
        case .completed: Constants.Green400
        case .pending: Constants.Warning500
        case .failed: Constants.Secondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy, HH:mm"
        return formatter
    }()

    /// Shared by the detail screen and the edit save path so a refresh never
    /// drifts from what the receipt already showed.
    static func map(
        _ detail: Components.Schemas.VaultTransactionDetailDto,
        fallbackName: String = ""
    ) -> VaultTransactionDetail {
        let feeMicro = UInt64(detail.feeMicro) ?? 0
        let amountUsdcMicro = UInt64(detail.amountUsdcMicro) ?? 0
        let feePercent = amountUsdcMicro > 0
            ? Double(feeMicro) / Double(amountUsdcMicro) * 100
            : 0
        let parsedDate: Date = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: detail.createdAt) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: detail.createdAt) ?? Date()
        }()
        return VaultTransactionDetail(
            amountVnd: UInt64(detail.amountVnd) ?? 0,
            recipientName: detail.recipientName,
            status: {
                switch detail.status {
                case "CONFIRMED": return .completed
                case "FAILED": return .failed
                default: return .pending
                }
            }(),
            date: parsedDate,
            bankName: detail.bankName,
            bankAccountNumber: detail.bankAccountNumber,
            feeVnd: UInt64(
                Double(feeMicro) / 1_000_000 * (Double(detail.rate) ?? 0)
            ),
            feePercent: feePercent,
            feeUsdc: Double(feeMicro) / 1_000_000,
            rate: UInt64(detail.rate) ?? 0,
            note: detail.note,
            name: detail.name ?? fallbackName,
            needsApproval: detail.needsApproval,
            canApprove: detail.canApprove,
            canCancel: detail.canCancel,
            canEdit: detail.canEdit,
            category: detail.category
                .flatMap { CategoryChip.Category(apiValue: $0.value1.rawValue) } ?? .other,
            paidByName: detail.paidBy?.value1.displayName,
            shareWithNames: detail.shareWith.map(\.displayName),
            shareWithUserIds: detail.shareWith.map(\.userId),
            madeByName: detail.madeBy?.value1.displayName ?? "",
            madeByAvatarUrl: detail.madeBy?.value1.avatarUrl,
            qrPayload: detail.qrPayload
        )
    }
}

#Preview {
    VaultTransactionDetailView(
        detail: VaultTransactionDetail(
            amountVnd: 200_000,
            recipientName: "Nguyen Van A",
            status: .completed,
            date: Date(timeIntervalSince1970: 1_784_000_000),
            bankName: "Techcombank",
            bankAccountNumber: "0271003061328",
            feeVnd: 1_155,
            feePercent: 0.7,
            feeUsdc: 0.01,
            rate: 26_500,
            note: "Chuyen tien",
            name: "Cafe",
            category: .coffee,
            paidByName: nil,
            shareWithNames: nil,
            shareWithUserIds: [],
            madeByName: "Cattie",
            madeByAvatarUrl: nil
        ),
        tripId: 1,
        vaultTransactionId: 1,
        onSendAgain: {}
    )
}
