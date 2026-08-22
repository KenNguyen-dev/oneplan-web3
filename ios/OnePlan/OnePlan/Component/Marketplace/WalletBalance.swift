//
//  WalletBalance.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI

struct WalletBalance: View {
    var balance: String = "0"
    var isBalanceHidden: Bool = false
    var onToggleVisibility: () -> Void = {}
    var onWithdraw: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Constants.White)
                        .frame(width: 20, height: 20)

                    Text("Wallet Balance")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundStyle(Constants.White)
                        .tracking(-0.7)
                }

                HStack(spacing: 12) {
                    Text(balance)
                        .font(Font.custom("SF Compact Rounded", size: 32).weight(.semibold))
                        .foregroundStyle(Constants.White)

                    Button(action: onToggleVisibility) {
                        Image(systemName: isBalanceHidden ? "eye.slash" : "eye")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Constants.White)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 8)

            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(height: 1)

            Button(action: onWithdraw) {
                Text("Withdraw")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundStyle(Constants.White)
                    .tracking(-0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 100, style: .continuous)
                            .fill(Color.white.opacity(0.72))
                            .overlay(
                                RoundedRectangle(cornerRadius: 100, style: .continuous)
                                    .fill(Color.white.opacity(0.2))
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 100, style: .continuous)
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(height: 208)
        .background(Color(red: 0.21, green: 0.21, blue: 0.21))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color(red: 0.15, green: 0.15, blue: 0.15), lineWidth: 4)
        )
    }
}

#Preview {
    WalletBalance()
        .padding()
        .background(Constants.Background)
}
