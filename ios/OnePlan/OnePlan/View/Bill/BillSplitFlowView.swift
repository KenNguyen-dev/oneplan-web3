//
//  BillSplitFlowView.swift
//  OnePlan
//
//  Created by ken on 29/3/26.
//

import Foundation
import SwiftUI
import OpenAPIRuntime

struct BillSplitFlowView: View {
    let tripId: Int
    let members: [TripMemberDto]
    /// Trip group (home) currency, resolved by the parent from its loaded
    /// trip. This view's own `service` is never loaded, so currency must be
    /// passed in.
    let groupCurrency: Currency?
    /// Trip primary local currency, resolved by the parent.
    let localCurrency: Currency?
    let onDismiss: () -> Void

    @State private var step: BillSplitStep = .capture
    @State private var capturedImage: UIImage?
    @State private var scanResult: Components.Schemas.ReceiptScanResultDto?
    @State private var restaurantName: String = ""
    @State private var mappedMembers: [DnDBillMemberItem] = []
    @State private var mappedBreakdownRows: [[DnDBillBreakdownItem]] = []
    @State private var errorMessage: String?
    @State private var service = TripDetailService()

    /// Receipt currency: trip local → trip group → Gemini-detected (only if
    /// it maps to a supported server currency) → VND. Local-first because
    /// Gemini misreads currency on non-Latin (e.g. all-Thai) receipts. The
    /// Gemini path is gated on the closed API enum, NOT `Currency(rawValue:)`
    /// (which never fails — it synthesizes a junk currency for symbols /
    /// unknown codes).
    private var receiptCurrency: Currency {
        if let localCurrency { return localCurrency }
        if let groupCurrency { return groupCurrency }
        if let raw = scanResult?.currency,
           let apiCurrency = Components.Schemas.Currency(
               rawValue: raw.uppercased()
           ),
           let mapped = Currency(from: apiCurrency) {
            return mapped
        }
        return .VND
    }

    private var showError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    enum BillSplitStep {
        case capture
        case parsing
        case assign
        case saving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch step {
                case .capture:
                    ScanBillView(
                        onBack: { onDismiss() },
                        onImageCaptured: { image in
                            capturedImage = image
                            step = .parsing
                            Task { await parseReceipt(image) }
                        }
                    )

                case .parsing:
                    parsingView

                case .assign:
                    if scanResult != nil {
                        DnDBillItemsView(
                            members: mappedMembers,
                            breakdownRows: mappedBreakdownRows,
                            currency: receiptCurrency,
                            restaurantName: $restaurantName,
                            onConfirm: { assignments in
                                step = .saving
                                Task { await saveExpenses(assignments, restaurantName: restaurantName) }
                            },
                            onDismiss: {
                                step = .capture
                                self.scanResult = nil
                                capturedImage = nil
                                errorMessage = nil
                            }
                        )
                    }

                case .saving:
                    savingView
                }

            }
        }
        .alert("Error", isPresented: showError) {
            Button("Retake") {
                errorMessage = nil
                step = .capture
                capturedImage = nil
                scanResult = nil
            }
        } message: {
            Text(errorMessage ?? String(localized: "Something went wrong."))
        }
    }

    // MARK: - Parsing View

    private var parsingView: some View {
        GeometryReader { proxy in
            if let capturedImage {
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: max(proxy.size.width - 40, 0),
                        height: max(proxy.size.height - 98, 0)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 40, style: .continuous)
                            .fill(.black.opacity(0.4))
                    }
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(1.5)
                            Text("Scanning receipt...")
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .top
                    )
                    .padding(.top, 0)
            }
        }
        .background(Constants.Background)
    }

    // MARK: - Saving View

    private var savingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Creating expense...")
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundStyle(Constants.ContentM)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Constants.Background)
    }

    // MARK: - Image Processing

    private func downsized(_ image: UIImage, maxDimension: CGFloat = 1024) -> UIImage {
        let size = image.size
        guard max(size.width, size.height) > maxDimension else { return image }
        let scale = maxDimension / max(size.width, size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - API Calls

    private func parseReceipt(_ image: UIImage) async {
        let resized = downsized(image)

        guard let imageData = resized.jpegData(compressionQuality: 0.85) else {
            errorMessage = String(localized: "Failed to process image.")
            return
        }

        do {
            let imagePayload = Components.Schemas.ScanReceiptDto.imagePayload(body: .init(imageData))
            let imagePart = OpenAPIRuntime.MultipartPart<Components.Schemas.ScanReceiptDto.imagePayload>(
                payload: imagePayload,
                filename: "receipt.jpg"
            )
            let multipartBody = OpenAPIRuntime.MultipartBody<Components.Schemas.ScanReceiptDto>([
                .image(imagePart)
            ])
            let input = Operations.scanReceipt.Input(
                path: .init(tripId: tripId),
                body: .multipartForm(multipartBody)
            )

            let response = try await APIClient.shared.scanReceipt(input)

            switch response {
            case .ok(let ok):
                let result = try ok.body.json
                if result.items.isEmpty {
                    errorMessage = String(localized: "No items detected in the receipt.")
                    return
                }
                scanResult = result
                restaurantName = result.restaurantName ?? String(localized: "Receipt")
                mappedMembers = mapMembers()
                mappedBreakdownRows = mapBreakdownRows(from: result)
                step = .assign
            case .created(let created):
                let result = try created.body.json
                if result.items.isEmpty {
                    errorMessage = String(localized: "No items detected in the receipt.")
                    return
                }
                scanResult = result
                restaurantName = result.restaurantName ?? String(localized: "Receipt")
                mappedMembers = mapMembers()
                mappedBreakdownRows = mapBreakdownRows(from: result)
                step = .assign
            case .forbidden:
                errorMessage = String(localized: "You don't have access to scan receipts for this trip.")
            case .unprocessableContent:
                errorMessage = String(localized: "Could not extract items from the receipt. Try a clearer photo.")
            case .undocumented(statusCode: let code, _):
                errorMessage = String(localized: "Unexpected server error (\(code)). Please try again.", comment: "%lld = HTTP status code")
            }
        } catch {
            errorMessage = String(localized: "Could not read the receipt. Try a clearer photo.")
        }
    }

    private func saveExpenses(
        _ assignments: [(itemName: String, amount: Double, memberUserIds: [Int])],
        restaurantName: String?
    ) async {
        let name = restaurantName ?? String(localized: "Receipt")
        let note = restaurantName.map { String(localized: "Receipt: \($0)", comment: "%@ = restaurant name") } ?? String(localized: "Receipt scan")

        let items = assignments.map {
            (name: $0.itemName, amount: $0.amount, userId: $0.memberUserIds[0])
        }

        // If the receipt was scanned in a currency different from the trip's
        // group currency, forward it as the expense's original currency. The
        // server derives the original total from the item-amount sum and
        // converts to the trip currency (same path as a manual expense).
        // Note: `groupCurrency` is passed in — the local `service` is never
        // loaded, so `service.homeCurrency` would always be nil here.
        let home = groupCurrency ?? .VND
        let isLocal = receiptCurrency != home

        let success = await service.createExpenseFromReceipt(
            tripId: tripId,
            restaurantName: name,
            items: items,
            receiptNote: note,
            originalCurrency: isLocal ? receiptCurrency : nil
        )

        if success {
            onDismiss()
        } else {
            errorMessage = service.error ?? String(localized: "Failed to create expense. Please try again.")
            step = .assign
        }
    }

    // MARK: - Data Mapping

    private func mapMembers() -> [DnDBillMemberItem] {
        members.filter { $0.inviteStatus.value1 == .ACCEPTED }.map { member in
            DnDBillMemberItem(
                userId: Int(member.userId),
                name: member.displayName,
                imageURL: member.avatarUrl ?? ""
            )
        }
    }

    private func mapBreakdownRows(from result: Components.Schemas.ReceiptScanResultDto) -> [[DnDBillBreakdownItem]] {
        // The scan API returns prices in MAJOR units exactly as printed
        // (e.g. 950.00 baht). The DnD engine works in integer minor units
        // for exact split arithmetic, so scale up here; `formatPrice` and
        // `buildConfirmData` scale back down by the same factor. VND
        // (decimalPlaces 0) ⇒ factor 1, unchanged.
        let minorFactor = pow(10.0, Double(receiptCurrency.decimalPlaces))
        let items = result.items.map { item -> DnDBillBreakdownItem in
            let unitMinor = Int((item.unitPrice * minorFactor).rounded())
            let totalMinor = Int((item.totalPrice * minorFactor).rounded())
            let displayPrice = item.quantity > 1 ? unitMinor : totalMinor
            return DnDBillBreakdownItem(
                name: item.name,
                quantity: item.quantity > 1 ? Int(item.quantity) : nil,
                price: DnDBillBreakdownItem.formatPrice(displayPrice, currency: receiptCurrency),
                priceValue: totalMinor
            )
        }

        // Arrange into rows of 2
        var rows: [[DnDBillBreakdownItem]] = []
        for i in stride(from: 0, to: items.count, by: 2) {
            let end = min(i + 2, items.count)
            rows.append(Array(items[i..<end]))
        }
        return rows
    }
}
