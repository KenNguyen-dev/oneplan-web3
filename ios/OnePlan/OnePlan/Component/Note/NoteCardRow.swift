//
//  NoteCardRow.swift
//  OnePlan
//
//  Note card row used inside the trip notes list.
//

import SwiftUI

/// A single trip note. View-layer model mapped from `TripNoteDto`. `id` is the
/// server-assigned note id.
struct TripNote: Identifiable, Equatable {
    let id: Int
    var title: String
    var body: String
    var date: Date
    var isDone: Bool

    init(
        id: Int,
        title: String,
        body: String,
        date: Date,
        isDone: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
        self.isDone = isDone
    }
}

extension TripNote {
    /// Maps a server note DTO into the view model. `createdAt` drives the card's
    /// displayed date.
    init(dto: Components.Schemas.TripNoteDto) {
        self.id = dto.id
        self.title = dto.title
        self.body = dto.body ?? ""
        self.date = TripNote.parseISODate(dto.createdAt) ?? Date()
        self.isDone = dto.isDone
    }

    /// Parses an ISO-8601 timestamp, tolerating Prisma's fractional seconds.
    static func parseISODate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

extension TripNote {
    /// Placeholder notes for SwiftUI previews only (real data comes from the API).
    static let samples: [TripNote] = {
        let calendar = Calendar.current
        func date(_ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day)) ?? Date()
        }
        return [
            TripNote(
                id: 1,
                title: "Đồ ăn nhẹ đi xe",
                body: "Đi xe hơi lâu nên mua một ít đồ ăn mang theo trên xe ăn cho đỡ bị buồn miệng. Mua ít trái cây với snack cho dễ mang Có thể mang theo mỗi người 1 chai nước suối nha, một hoặc hai chai",
                date: date(5, 15),
                isDone: false
            ),
            TripNote(
                id: 2,
                title: "Dresscode ngày 1 Nâu+Đen",
                body: "Nam quần đen áo nâu\nNữ đầm nâu, phụ kiện đen nha.",
                date: date(5, 14),
                isDone: true
            ),
            TripNote(
                id: 3,
                title: "Lịch trình ngày 2",
                body: "Sáng đi chợ đêm Đà Lạt, trưa ăn bánh căn, chiều tham quan vườn hoa.",
                date: date(5, 13),
                isDone: false
            ),
        ]
    }()
}

/// Card-style row matching the Figma note design: a checkbox + title + date
/// header over a multi-line body, on a rounded neutral surface.
struct NoteCardRow: View {
    let note: TripNote
    /// Tapping the card (anywhere but the checkbox) opens it for editing.
    var onTap: (() -> Void)? = nil
    /// Toggles the note's completed state when the checkbox is tapped.
    var onToggle: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd/MM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Text(note.body)
                .font(.beVietnamPro(15))
                .tracking(-0.3)
                .lineSpacing(2)
                .foregroundStyle(Constants.Neutral900)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.Neutral50)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                checkbox
            }
            .buttonStyle(.plain)

            Text(note.title)
                .font(.beVietnamPro(16, weight: .medium))
                .tracking(-0.32)
                .foregroundStyle(Constants.ContentB)
                .strikethrough(note.isDone, color: Constants.ContentB)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(Self.dateFormatter.string(from: note.date))
                .font(.beVietnamPro(14))
                .tracking(-0.28)
                .foregroundStyle(Constants.Neutral700)
                .lineLimit(1)
        }
        .padding(.bottom, 6)
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(note.isDone ? Constants.BlueBase : Constants.White)
            .overlay {
                if note.isDone {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Constants.White)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Constants.Neutral200, lineWidth: 1)
                }
            }
            .frame(width: 20, height: 20)
    }
}

#Preview {
    VStack(spacing: 8) {
        NoteCardRow(
            note: TripNote(
                id: 1,
                title: "Đồ ăn nhẹ đi xe",
                body: "Đi xe hơi lâu nên mua một ít đồ ăn mang theo trên xe ăn cho đỡ bị buồn miệng. Mua ít trái cây với snack cho dễ mang",
                date: Date(),
                isDone: false
            ),
            onToggle: {}
        )
        NoteCardRow(
            note: TripNote(
                id: 2,
                title: "Dresscode ngày 1 Nâu+Đen",
                body: "Nam quần đen áo nâu\nNữ đầm nâu, phụ kiện đen nha.",
                date: Date(),
                isDone: true
            ),
            onToggle: {}
        )
    }
    .padding()
    .background(Constants.White)
}
