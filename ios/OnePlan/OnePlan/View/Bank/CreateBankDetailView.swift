//
//  CreateBankDetailView.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import SwiftUI
import UIKit

struct CreateBankDetailView: View {
    @State private var bankName = ""
    @State private var accountNumber = ""
    @State private var accountName = ""

    var body: some View {
        ZStack {
            Constants.Background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                formCard
                    .padding(.top, 16)

                Spacer(minLength: 16)

                PrimaryButton(title: "Save") {
                    // Hook save action here when API/state is ready.
                }
                .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
        }
    }

    private var formCard: some View {
        VStack(spacing: 0) {
            bankRow(
                title: "Bank name",
                placeholder: "Enter",
                text: $bankName,
                keyboardType: .default
            )

            Divider()
                .background(Constants.DividerStroke)

            bankRow(
                title: "Account number",
                placeholder: "Enter",
                text: $accountNumber,
                keyboardType: .numberPad
            )

            Divider()
                .background(Constants.DividerStroke)

            bankRow(
                title: "Name",
                placeholder: "Bank account name",
                text: $accountName,
                keyboardType: .default
            )
        }
        .padding(12)
        .background(Constants.Surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func bankRow(
        title: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .foregroundColor(Constants.ContentM)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(placeholder, text: text)
                .font(Font.beVietnamPro(14, weight: .medium))
                .foregroundColor(text.wrappedValue.isEmpty ? Constants.ContentL : Constants.ContentB)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .keyboardType(keyboardType)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 16)
    }
}

#Preview {
    CreateBankDetailView()
}
