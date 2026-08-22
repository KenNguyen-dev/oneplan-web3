//
//  BankDetailView.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI
import UIKit

struct BankDetailView: View {
    private struct BankDetailItem: Identifiable {
        let id = UUID()
        let label: String
        let value: String
    }

    private let bankDetails: [BankDetailItem] = [
        .init(label: "Name", value: "Nguyen Thi Thanh Huong"),
        .init(label: "Bank name", value: "Vietcombank"),
        .init(label: "Bank account number", value: "051389890789"),
    ]

    var body: some View {
        ZStack {
            Constants.Background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                detailCard
                    .padding(.top, 16)

                Spacer(minLength: 16)

                SecondaryButton(title: "Delete bank account", variant: .danger) {
                    // Hook delete flow here when API/state is ready.
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private var detailCard: some View {
        VStack(spacing: 0) {
            ForEach(bankDetails) { item in
                detailRow(item: item)
            }
        }
        .padding(.vertical, 6)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(item: BankDetailItem) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.label)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentM)
                    .lineLimit(1)

                Text(item.value)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .foregroundColor(Constants.ContentB)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                UIPasteboard.general.string = item.value
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18))
                    .foregroundColor(Constants.ContentB)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Copy \(item.label)"))
        }
        .padding(14)
    }
}

#Preview {
    BankDetailView()
}
