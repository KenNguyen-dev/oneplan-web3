//
//  WithdrawView.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI

struct WithdrawView: View {
    private let withdrawAccount = "Vietcombank ***0789"
    private let withdrawAmount = "200,000"
    private let walletBalance = "Wallet balance: 46,800,000 VND"

    var body: some View {
        ZStack {
            Constants.Background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                withdrawCard
                    .padding(.top, 16)

                Spacer(minLength: 16)

                Text("Withdrawal processing time is approximately 2-3 business days.")
                  .font(Font.custom("Be Vietnam Pro", size: 14))
                  .multilineTextAlignment(.center)
                  .foregroundColor(Constants.ContentM)
                  .padding(.bottom, 8)
                  .frame(maxWidth: .infinity, alignment: .top)
                
                PrimaryButton(title: "Withdraw") {
                    // Hook withdraw flow here when API/state is ready.
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private var withdrawCard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.21, green: 0.21, blue: 0.21))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(red: 0.15, green: 0.15, blue: 0.15), lineWidth: 4)
                )

            VStack(spacing: 0) {
                headerRow
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                Rectangle()
                    .fill(Color(red: 0.36, green: 0.36, blue: 0.36))
                    .frame(height: 1)

                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Label {
                        Text("Withdraw amount")
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                    } icon: {
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 14, weight: .regular))
                    }
                    .foregroundColor(.white)

                    Text(withdrawAmount)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                }

                Spacer(minLength: 0)

                walletBadge
                    .padding(.bottom, 14)
            }
        }
        .frame(height: 352)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Constants.Surface)

                Image(systemName: "arrow.up")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Constants.BlueBase)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text("Withdraw to")
                    .font(.system(size: 12))
                    .foregroundColor(Constants.ContentM)

                Text(withdrawAccount)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private var walletBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(red: 0.22, green: 0.22, blue: 0.22))

            Text(walletBalance)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(Color(red: 0.22, green: 0.22, blue: 0.22))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(red: 0.81, green: 0.81, blue: 0.81))
        .clipShape(Capsule())
    }
}

#Preview {
    WithdrawView()
}
