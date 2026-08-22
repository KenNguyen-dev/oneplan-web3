//
//  PlanItem.swift
//  OnePlan
//
//  Created by ken on 26/2/26.
//

import SwiftUI

struct PlanItem: View {
    private enum VoiceStyle {
        case blue
        case gray

        var colors: [Color] {
            switch self {
            case .blue:
                return [Constants.BlueAlpha10, Color(red: 0, green: 0.31, blue: 0.85)]
            case .gray:
                return [Constants.Neutral200, Constants.Neutral600]
            }
        }

        var playIconColor: Color {
            switch self {
            case .blue:
                return Constants.BlueBase
            case .gray:
                return Constants.Neutral600
            }
        }

        var textColor: Color {
            switch self {
            case .blue:
                return Constants.White
            case .gray:
                return Constants.Surface
            }
        }
    }

    let title: String
    let location: String
    let markerColor: Color
    let description: String?
    let voiceDuration: String?
    let isVoiceGray: Bool

    init(
        title: String = "Breakfast",
        location: String = "Burj Khalifa, Dubai, UAE",
        markerColor: Color = Constants.Warning500,
        description: String? = "Try Shawarma, Hummus and Falafel",
        voiceDuration: String? = "1:12",
        isVoiceGray: Bool = false
    ) {
        self.title = title
        self.location = location
        self.markerColor = markerColor
        self.description = description
        self.voiceDuration = voiceDuration
        self.isVoiceGray = isVoiceGray
    }

    private var voiceStyle: VoiceStyle {
        isVoiceGray ? .gray : .blue
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HStack(alignment: .center, spacing: 6) {
                        Rectangle()
                            .frame(width: 12, height: 12)
                            .foregroundColor(markerColor)
                            .cornerRadius(.infinity)

                        // Title
                        Text(title)
                            .font(
                                Font.beVietnamPro(16, weight: .medium)
                            )
                            .foregroundColor(Constants.ContentB)
                    }
                    .padding(0)

                    if !location.isEmpty {
                        HStack(alignment: .center, spacing: 6) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Constants.ContentM)

                            // Note
                            Text(location)
                                .font(Font.custom("Be Vietnam Pro", size: 14))
                                .foregroundColor(Constants.ContentM)
                        }
                        .padding(0)
                        .cornerRadius(5)
                    }
                }

                Spacer()

                if let voiceDuration {
                    HStack(alignment: .center, spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(voiceStyle.playIconColor)
                            .frame(width: 24, height: 24, alignment: .center)
                            .background(Constants.Surface)
                            .clipShape(.circle)

                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(voiceStyle.textColor)

                        Text(voiceDuration)
                            .font(Font.custom("Be Vietnam Pro", size: 14))
                            .foregroundColor(voiceStyle.textColor)
                    }
                    .padding(.leading, 3)
                    .padding(.trailing, 8)
                    .padding(.vertical, 3)
                    .frame(minWidth: 108, alignment: .leading)
                    .background(
                        LinearGradient(
                            colors: voiceStyle.colors,
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(26)
                }
            }

            if let description, !description.isEmpty {
                Text(description)
                    .font(Font.custom("Be Vietnam Pro", size: 14))
                    .foregroundColor(Constants.ContentB)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
                    .background(Constants.Background)
                    .cornerRadius(12)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            alignment: .topLeading
        )
        .background(Constants.Surface)
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.06), radius: 8.95, x: 0, y: 0)
    }
}

#Preview {
    VStack(spacing: 12) {
        PlanItem()
        PlanItem(
            title: "Grocery",
            location: "Al Barsha, Dubai, UAE",
            markerColor: Constants.Warning500,
            description: "Beef, Veges, Pasta and Italian Noodles",
            voiceDuration: "1:12",
            isVoiceGray: true
        )
    }
    .padding()
    .background(Constants.Background)
}
