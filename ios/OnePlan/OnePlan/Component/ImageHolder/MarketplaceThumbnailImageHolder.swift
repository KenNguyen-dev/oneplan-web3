//
//  MarketplaceThumbnailImageHolder.swift
//  OnePlan
//
//  Created by ken on 26/3/26.
//

import PhotosUI
import SwiftUI

struct MarketplaceThumbnailImageHolder: View {
    private let defaultSize: CGFloat = 72
    private let baseLogoBadgeCornerRadius: CGFloat = 6.43
    private let baseLogoBadgeBottomRightCornerRadius: CGFloat = 14.9
    private let baseCornerRadius: CGFloat = 14.9
    private let baseBorderWidth: CGFloat = 2.48
    private let baseLogoBadgeSize: CGFloat = 24.1
    private let baseLogoBadgeBorderWidth: CGFloat = 1
    private let baseCameraIconSize: CGFloat = 20

    var thumbnailImageName: String? = nil
    var thumbnailUrl: String? = nil
    var thumbnailImage: UIImage? = nil
    var size: CGFloat? = nil
    var logoImageName: String = "appLogoDark"
    var editable: Bool = false
    var onImageSelected: ((UIImage) -> Void)? = nil

    @State private var pickerItem: PhotosPickerItem?

    private var resolvedSize: CGFloat {
        size ?? defaultSize
    }

    private var scaleFactor: CGFloat {
        resolvedSize / defaultSize
    }

    private var cornerRadius: CGFloat {
        baseCornerRadius * scaleFactor
    }

    private var borderWidth: CGFloat {
        baseBorderWidth * scaleFactor
    }

    private var logoBadgeCornerRadius: CGFloat {
        baseLogoBadgeCornerRadius * scaleFactor
    }

    private var logoBadgeBottomRightCornerRadius: CGFloat {
        baseLogoBadgeBottomRightCornerRadius * scaleFactor
    }

    private var logoBadgeSize: CGFloat {
        baseLogoBadgeSize * scaleFactor
    }

    private var logoBadgeBorderWidth: CGFloat {
        baseLogoBadgeBorderWidth * scaleFactor
    }

    private var cameraIconSize: CGFloat {
        baseCameraIconSize * scaleFactor
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let uiImage = thumbnailImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let urlString = thumbnailUrl, let url = URL(string: urlString) {
                    CachedRemoteImage(
                        url: url,
                        targetSize: CGSize(width: resolvedSize, height: resolvedSize)
                    ) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Rectangle().fill(Constants.Neutral50)
                    }
                } else if let name = thumbnailImageName {
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Constants.Neutral50)
                }
            }
            .frame(width: resolvedSize, height: resolvedSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Constants.Black, lineWidth: borderWidth)
            )
            .overlay {
                if editable {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(Constants.Black.opacity(0.3))
                            .frame(width: resolvedSize, height: resolvedSize)
                            .overlay {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: cameraIconSize))
                                    .foregroundStyle(Constants.White)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Image(logoImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: logoBadgeSize, height: logoBadgeSize)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: logoBadgeCornerRadius,
                        bottomLeadingRadius: logoBadgeCornerRadius,
                        bottomTrailingRadius: logoBadgeBottomRightCornerRadius,
                        topTrailingRadius: logoBadgeCornerRadius
                    )
                )
                .overlay(
                    UnevenRoundedRectangle(
                        topLeadingRadius: logoBadgeCornerRadius,
                        bottomLeadingRadius: logoBadgeCornerRadius,
                        bottomTrailingRadius: logoBadgeBottomRightCornerRadius,
                        topTrailingRadius: logoBadgeCornerRadius
                    )
                    .stroke(Constants.Black, lineWidth: logoBadgeBorderWidth)
                )
        }
        .frame(width: resolvedSize, height: resolvedSize)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    onImageSelected?(image)
                }
            }
        }
    }
}

#Preview {
    MarketplaceThumbnailImageHolder(thumbnailImageName: "defaultTripPlaceholder")
        .padding()
        .background(Constants.Background)
}
