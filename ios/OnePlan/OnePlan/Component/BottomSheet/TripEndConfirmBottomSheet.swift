//
//  TripEndConfirmBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 8/3/26.
//

import SwiftUI

struct TripEndConfirmBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let amount: Double
    let isReceiving: Bool
    let onConfirm: () async -> Void

    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()

                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Constants.OnSurface)
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Constants.ContentM)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(
                            isReceiving
                                ? Color(red: 0.70, green: 0.93, blue: 0.86)
                                : Color(red: 0.93, green: 0.70, blue: 0.70)
                        )

                    Image(systemName: isReceiving ? "tray.and.arrow.down" : "tray.and.arrow.up")
                        .font(.system(size: 46, weight: .light))
                        .foregroundColor(Constants.Surface)
                }
                .frame(width: 80, height: 80)

                VStack(spacing: 8) {
                    Text(isReceiving
                        ? String(localized: "Are you confirm that you've received")
                        : String(localized: "Are you confirm that you've paid"))
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(Constants.ContentB)
                        .multilineTextAlignment(.center)

                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(CurrencyFormatter.symbol)
                            .font(Font.custom("Be Vietnam Pro", size: 36))
                            .foregroundColor(Constants.ContentL)
                        Text(CurrencyFormatter.formatWhole(amount))
                            .font(Font.custom("Be Vietnam Pro", size: 36))
                            .foregroundColor(Constants.ContentB)
                        Text(CurrencyFormatter.formatDecimal(amount))
                            .font(Font.custom("Be Vietnam Pro", size: 36))
                            .foregroundColor(Constants.ContentL)
                    }
                }
            }
            .padding(.top, 18)

            Spacer()

            Button {
                isConfirming = true
                Task {
                    await onConfirm()
                    isConfirming = false
                    dismiss()
                }
            } label: {
                if isConfirming {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                } else {
                    Text("Confirm")
                        .font(
                            Font.beVietnamPro(16, weight: .medium)
                        )
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
            }
            .disabled(isConfirming)
            .background(Constants.BlueBase)
            .cornerRadius(.infinity)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(392)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TripEndConfirmBottomSheet(
                amount: 7_000_000,
                isReceiving: true,
                onConfirm: {}
            )
        }
}
