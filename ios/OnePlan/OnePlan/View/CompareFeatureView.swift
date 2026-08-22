//
//  CompareFeatureView.swift
//  OnePlan
//
//  Created by ken on 27/3/26.
//

import SwiftUI

struct CompareFeatureView: View {
    private let unlockWithProRows: [FeatureComparisonRow] = [
        FeatureComparisonRow(
            title: "Trips planning",
            basic: .text("Limited"),
            pro: .text("Unlimited")
        ),
        FeatureComparisonRow(
            title: "Extract pins by social video",
            basic: .text("02"),
            pro: .text("Renewable")
        ),
        FeatureComparisonRow(
            title: "Upload plans on market",
            basic: .text("-"),
            pro: .check
        ),
        FeatureComparisonRow(
            title: "Trip insights",
            basic: .text("-"),
            pro: .check
        ),
        FeatureComparisonRow(
            title: "AI bill split",
            basic: .text("-"),
            pro: .check
        ),
    ]

    private let includedInAllPlansRows: [FeatureComparisonRow] = [
        FeatureComparisonRow(title: "Create trips", basic: .check, pro: .check),
        FeatureComparisonRow(
            title: "Build plans manual",
            basic: .check,
            pro: .check
        ),
        FeatureComparisonRow(
            title: "Unlimited boards",
            basic: .check,
            pro: .check
        ),
        FeatureComparisonRow(
            title: "Unlimited add friends",
            basic: .check,
            pro: .check
        ),
        FeatureComparisonRow(
            title: "Invite friends",
            basic: .check,
            pro: .check
        ),
        FeatureComparisonRow(
            title: "Trip passport",
            basic: .check,
            pro: .check
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 8) {
                Text("Compare features")
                    .font(Font.custom("Be Vietnam Pro", size: 20))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Constants.Neutral950)
                    .frame(maxWidth: .infinity, alignment: .top)

                Text(
                    "OnePlan combines your essential travel planning tools in one place, helping you organize trips more easily and unlock more powerful features with Pro."
                )
                .font(Font.custom("Be Vietnam Pro", size: 13))
                .multilineTextAlignment(.center)
                .foregroundColor(Constants.Neutral950)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .padding(0)
            .frame(maxWidth: .infinity, alignment: .top)

            VStack(spacing: 0) {
                sectionHeader(title: "Unlock with Pro", icon: .crown)
                ForEach(Array(unlockWithProRows.enumerated()), id: \.element.id)
                { index, row in
                    featureRow(row, showTopDivider: index == 0)
                }

                sectionHeader(title: "Included in all plans", icon: .check)
                ForEach(
                    Array(includedInAllPlansRows.enumerated()),
                    id: \.element.id
                ) { index, row in
                    featureRow(row, showTopDivider: index == 0)
                }
            }
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
        .background(Constants.Neutral50)
    }

    private func sectionHeader(title: String, icon: HeaderIcon) -> some View {
        HStack(spacing: 5) {
            headerIcon(icon)
                .frame(width: 20, height: 20)

            Text(title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.56)
                .foregroundStyle(Constants.BlueBase)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                Text("Basic")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.Neutral950)
                    .frame(maxWidth: .infinity)

                Text("Pro")
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .tracking(-0.56)
                    .foregroundStyle(Constants.BlueBase)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(Constants.White)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Constants.BlueBase, lineWidth: 1)
                    )
            }
            .frame(width: 122)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }

    private func featureRow(
        _ row: FeatureComparisonRow,
        showTopDivider: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            Text(row.title)
                .font(Font.custom("Be Vietnam Pro", size: 14))
                .tracking(-0.56)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                featureValueCell(row.basic)
                    .frame(width: 61)

                featureValueCell(row.pro)
                    .frame(width: 61)
            }
            .frame(width: 122)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Constants.White)
        .overlay(alignment: .top) {
            if showTopDivider {
                Rectangle()
                    .fill(Constants.Neutral200)
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Constants.Neutral200)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func headerIcon(_ icon: HeaderIcon) -> some View {
        switch icon {
        case .crown:
            Image(systemName: "crown.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Constants.BlueBase)
                .frame(width: 16, height: 12)
        case .check:
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Constants.BlueBase)
                .frame(width: 17, height: 17)
        }
    }

    @ViewBuilder
    private func featureValueCell(_ value: FeatureValue) -> some View {
        switch value {
        case .text(let content):
            Text(content)
                .font(
                    Font.custom(
                        "Be Vietnam Pro",
                        size: content == "-" ? 14 : 13
                    )
                )
                .tracking(content == "-" ? -0.56 : -0.52)
                .foregroundStyle(Constants.Neutral950)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        case .check:
            checkCircleIcon(size: 17)
                .frame(maxWidth: .infinity)
        }
    }

    private func checkCircleIcon(size: CGFloat) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Constants.White, Constants.BlueBase.opacity(0.55))
            .frame(width: size, height: size)
    }
}

private struct FeatureComparisonRow: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let basic: FeatureValue
    let pro: FeatureValue
}

private enum FeatureValue {
    case text(LocalizedStringKey)
    case check
}

private enum HeaderIcon {
    case crown
    case check
}

#Preview {
    CompareFeatureView()
}
