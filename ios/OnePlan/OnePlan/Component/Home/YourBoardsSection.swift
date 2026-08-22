//
//  YourBoardsSection.swift
//  OnePlan
//
//  Created by ken on 3/7/26.
//
//  "Your Boards" section on Home (Figma 3823:17503): the user's boards
//  rendered with the existing BoardSummaryRow. "See all" switches to the
//  Board tab. Hosts must register `.navigationDestination(for:
//  BoardSummaryDto.self)` for the row pushes.
//

import SwiftUI

struct YourBoardsSection: View {
    let boards: [BoardSummaryDto]
    let onSeeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HomeSectionHeader(title: "Your Boards", onSeeAll: onSeeAll)

            ForEach(boards, id: \.id) { board in
                NavigationLink(value: board) {
                    BoardSummaryRow(board: board)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
