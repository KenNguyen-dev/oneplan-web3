//
//  GroupSettingsBottomSheet.swift
//  OnePlan
//
//  Created by Codex on 8/3/26.
//

import SwiftUI

struct GroupSettingsBottomSheet: View {
    @Binding var isPresented: Bool

    var onClose: () -> Void = {}
    var onSave: () -> Void = {}
    var onLeaveGroup: () -> Void = {}
    var onEndTrip: () -> Void = {}
    var isCreator: Bool = false

    var body: some View {
        BottomSheet(isPresented: $isPresented, sheetHeight: 260) { dismiss in
            VStack(spacing: 12) {
                toolbar(dismiss: dismiss)

                settingsCard

                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private func toolbar(dismiss: @escaping () -> Void) -> some View {
        HStack(alignment: .center) {
            Button {
                onClose()
                dismiss()
            } label: {
                ZStack {
                    Circle()
                        .fill(Constants.OnSurface)
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(Constants.ContentM)
                }
                .frame(width: 43, height: 43)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Group settings")
                .font(Font.custom("Be Vietnam Pro", size: 18))
                .foregroundColor(Constants.ContentB)

            Spacer()

            // Button {
            //     onSave()
            //     dismiss()
            // } label: {
            //     ZStack {
            //         Circle()
            //             .fill(Constants.BlueBase)
            //         Image(systemName: "checkmark")
            //             .font(.system(size: 18, weight: .semibold))
            //             .foregroundColor(.white)
            //     }
            //     .frame(width: 43, height: 43)
            // }
            // .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            settingRow(
                icon: "chart.bar.xaxis",
                title: "Analytics",
                value: String(localized: "Analytics")
            )

            Divider()
                .overlay(Constants.Neutral200)
                .padding(.leading, 58)

            settingRow(
                icon: "wallet.pass",
                title: "Currency",
                value: "VND (đ)"
            )
        }
        .padding(.vertical, 5)
        .background(Constants.Surface)
        .cornerRadius(25.4)
    }

    private func settingRow(icon: String, title: LocalizedStringKey, value: String)
        -> some View
    {
        HStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(Constants.ContentB)
                .frame(width: 43, height: 43)

            Text(title)
                .font(.system(size: 16))
                .foregroundColor(Constants.ContentB)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.system(size: 16))
                .foregroundColor(Constants.ContentB)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
    }

    private var actionButtons: some View {
        HStack(spacing: 7) {
            if !isCreator {
                SecondaryButton(title: "Leave group", variant: .dark) {
                    onLeaveGroup()
                }
            }

            if isCreator {
                SecondaryButton(title: "End trip", variant: .danger) {
                    onEndTrip()
                }
            }
        }
    }
}

#Preview {
    GroupSettingsBottomSheet(isPresented: .constant(true))
}
