//
//  AddingPinToBoardBottomSheet.swift
//  OnePlan
//
//  Created by ken on 11/5/26.
//

import SwiftUI

struct AddingPinBoardOption: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let pinCount: Int
    let location: String
    let coverImageUrl: String?

    init(
        id: String? = nil,
        title: String,
        description: String,
        pinCount: Int,
        location: String,
        coverImageUrl: String? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.description = description
        self.pinCount = pinCount
        self.location = location
        self.coverImageUrl = coverImageUrl
    }
}

struct AddingPinToBoardBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    let boards: [AddingPinBoardOption]
    var onSelectBoard: (AddingPinBoardOption) -> Void
    var onCreateBoard: () -> Void

    @State private var selectedBoardID: String?

    init(
        boards: [AddingPinBoardOption] = Self.previewBoards,
        selectedBoardID: String? = nil,
        onSelectBoard: @escaping (AddingPinBoardOption) -> Void = { _ in },
        onCreateBoard: @escaping () -> Void = {}
    ) {
        self.boards = boards
        self.onSelectBoard = onSelectBoard
        self.onCreateBoard = onCreateBoard
        _selectedBoardID = State(initialValue: selectedBoardID)
    }

    var body: some View {
        VStack(spacing: 20) {
            header
            // The board list can exceed the fixed sheet height, so it must
            // scroll — a plain VStack clips everything past the sheet edge.
            ScrollView {
                boardSection
                    .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 14)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Neutral50)
        .presentationDetents([.height(640)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Adding to Board")
                .font(.custom("Be Vietnam Pro", size: 20))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.8)
                .lineLimit(1)

            Text("Please select a Board to add to.")
                .font(.custom("Be Vietnam Pro", size: 13))
                .foregroundStyle(Constants.Neutral950)
                .tracking(-0.65)
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .frame(width: 319)
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Boards")
                .font(.beVietnamPro(16, weight: .medium))
                .foregroundStyle(Constants.ContentM)
                .tracking(-0.32)
                .lineLimit(1)

            VStack(spacing: 8) {
                ForEach(boards) { board in
                    Button {
                        selectedBoardID = board.id
                        onSelectBoard(board)
                    } label: {
                        AddingPinBoardRow(
                            board: board,
                            isSelected: selectedBoardID == board.id
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(board.title), \(board.pinCount) pins, \(board.location)")
                    .accessibilityAddTraits(selectedBoardID == board.id ? .isSelected : [])
                }

                Button(action: onCreateBoard) {
                    Text("Create new Board")
                        .font(.custom("Be Vietnam Pro", size: 17))
                        .foregroundStyle(Constants.BlueBase)
                        .tracking(-0.85)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Constants.BlueAlpha10)
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(
                                    Constants.BlueBase,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Create new Board")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static let previewBoards = [
        AddingPinBoardOption(
            title: "Local Spots in Ho Chi Minh",
            description: "Là trung tâm hiện đại lớn của Việt Nam, thành phố Hồ Chí Minh mang đến cái nhìn tổng quan về tương lai và quá khứ của đất nước.",
            pinCount: 24,
            location: "Ho Chi Minh"
        ),
        AddingPinBoardOption(
            title: "Best places in Da Nang",
            description: "Using AI to describe this list based on all pin inside this list.",
            pinCount: 24,
            location: "Da Nang"
        )
    ]
}

private struct AddingPinBoardRow: View {
    let board: AddingPinBoardOption
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CachedRemoteImage(
                url: URL(string: board.coverImageUrl ?? ""),
                targetSize: CGSize(width: 200, height: 240)
            ) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image("boardPlaceholder").resizable().scaledToFill()
            }
            .frame(width: 100, height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(board.title)
                            .font(.custom("Be Vietnam Pro", size: 18))
                            .foregroundStyle(Constants.Neutral950)
                            .tracking(-0.36)
                            .lineLimit(1)

                        Text(board.description)
                            .font(.custom("Be Vietnam Pro", size: 13))
                            .foregroundStyle(Constants.Neutral950)
                            .tracking(-0.65)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    AddingPinBoardCheckBox(isSelected: isSelected)
                }

                HStack(spacing: 0) {
                    AddingPinBoardMetaItem(
                        iconName: "boardPinIcon",
                        title: "\(board.pinCount) pins"
                    )

                    Rectangle()
                        .fill(Constants.Neutral100)
                        .frame(width: 1, height: 22)
                        .padding(.horizontal, 10)

                    AddingPinBoardMetaItem(
                        iconName: "boardCompassIcon",
                        title: board.location
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Constants.Neutral50, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Constants.Surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct AddingPinBoardMetaItem: View {
    let iconName: String
    let title: String

    var body: some View {
        HStack(spacing: 4) {
            Image(iconName)
                .resizable()
                .renderingMode(.original)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(title)
                .font(.custom("Be Vietnam Pro", size: 15))
                .foregroundStyle(Constants.Neutral700)
                .tracking(-0.3)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct AddingPinBoardCheckBox: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Constants.BlueBase : Constants.Surface)
                .overlay {
                    Circle()
                        .stroke(isSelected ? Constants.BlueBase : Color(red: 0.78, green: 0.78, blue: 0.78), lineWidth: 1)
                }

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Constants.White)
            }
        }
        .frame(width: 20, height: 20)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            AddingPinToBoardBottomSheet()
        }
}
