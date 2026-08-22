//
//  InvitationView.swift
//  OnePlan
//
//  Created by ken on 8/3/26.
//

import SwiftUI
import UIKit

struct TripInvitationView: View {
    let inviteCode: String
    var onJoined: (Int) -> Void = { _ in }
    var onDismiss: () -> Void = {}

    @Environment(UserProfileService.self) private var userProfileService
    @State private var tripService = TripService()
    @State private var invitePreview: InvitePreviewDto?
    @State private var joinedTrip: TripDto?
    @State private var isJoining = false
    @State private var errorMessage: String?
    @State private var showOngoingConflictAlert = false

    var body: some View {
        ZStack(alignment: .top) {
            Image("inviteBackground")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            invitationBody
                .padding(.top, 100)
        }
        .overlay(alignment: .bottom) {
            DismissButton(action: onDismiss)
                .padding(.bottom, 60)
        }
        .alert(
            "Already on a Trip",
            isPresented: $showOngoingConflictAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let existingTrip = tripService.ongoingTrips.first {
                Text(
                    "You're currently on \"\(existingTrip.name)\". End that trip before joining another ongoing trip."
                )
            } else {
                Text("You already have an ongoing trip. End it before joining another.")
            }
        }
    }

    private struct DismissButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(
                                        color: Color(
                                            red: 0.925,
                                            green: 0.925,
                                            blue: 0.925
                                        ),
                                        location: 0
                                    ),
                                    .init(
                                        color: Color(
                                            red: 0.7,
                                            green: 0.7,
                                            blue: 0.7
                                        ),
                                        location: 0.745
                                    ),
                                    .init(
                                        color: Color(
                                            red: 0.922,
                                            green: 0.922,
                                            blue: 0.922
                                        ),
                                        location: 1
                                    ),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Circle()
                        .fill(Constants.White.opacity(0.85))
                        .frame(width: 43.658, height: 16.346)
                        .blur(radius: 2.3)
                        .offset(y: -18)
                        .blendMode(.plusLighter)

                    Image(systemName: "xmark")
                        .font(.system(size: 17.8, weight: .light))
                        .foregroundStyle(Constants.ContentB.opacity(0.85))
                }
                .frame(width: 52, height: 52)
                .overlay {
                    Circle()
                        .stroke(Constants.White, lineWidth: 1.5)
                }
                .shadow(
                    color: Color(red: 0.588, green: 0.588, blue: 0.588).opacity(
                        0.25
                    ),
                    radius: 5.7,
                    x: 0,
                    y: 13
                )
                .shadow(
                    color: Color(red: 0.765, green: 0.765, blue: 0.765).opacity(
                        0.39
                    ),
                    radius: 3.05,
                    x: 0,
                    y: 3
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var invitationBody: some View {
        VStack {
            VStack(spacing: 6) {
                if isJoining {
                    Text("Joining group...")
                        .font(Font.custom("Be Vietnam Pro", size: 24))
                        .multilineTextAlignment(.center)
                        .tracking(-0.96)
                        .foregroundStyle(Constants.ContentB)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(Font.custom("Be Vietnam Pro", size: 18))
                        .multilineTextAlignment(.center)
                        .tracking(-0.72)
                        .foregroundStyle(.red)
                } else {
                    Text("You've got an invitation to\njoin a group")
                        .font(Font.custom("Be Vietnam Pro", size: 24))
                        .multilineTextAlignment(.center)
                        .tracking(-0.96)
                        .foregroundStyle(Constants.ContentB)

                    Text("Drag to join")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .tracking(-0.6)
                        .foregroundStyle(Constants.ContentM)
                }
            }

            InvitationDragPreview(
                coverImageUrl: previewCoverImageUrl,
                avatarUrl: userProfileService.profile?.avatarUrl,
                isJoining: isJoining,
                showingConflictAlert: showOngoingConflictAlert,
                onJoinTriggered: {
                    if hasOngoingTripConflict {
                        showOngoingConflictAlert = true
                    } else {
                        Task { await joinTrip() }
                    }
                }
            )

            VStack(spacing: 8) {
                Text(previewTripName)
                    .font(Font.custom("Be Vietnam Pro", size: 24))
                    .tracking(-0.96)
                    .foregroundStyle(Constants.ContentB)

                HStack(spacing: 3) {
                    MemberAvatarStrip(
                        members: joinedTrip?.members ?? []
                    )
                    Text("\(previewMemberCount) members in this group")
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .tracking(-0.6)
                        .foregroundStyle(Constants.ContentM)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: inviteCode) {
            await loadInvitePreview()
        }
    }

    private var previewCoverImageUrl: String? {
        joinedTrip?.coverImageUrl ?? invitePreview?.coverImageUrl
    }

    private var previewTripName: String {
        joinedTrip?.name ?? invitePreview?.name ?? "Trip"
    }

    private var previewMemberCount: Int {
        joinedTrip?.members.count ?? invitePreview?.memberCount ?? 0
    }

    private var hasOngoingTripConflict: Bool {
        guard let preview = invitePreview,
              preview.status.value1 == .ONGOING else { return false }
        return !tripService.ongoingTrips.isEmpty
    }

    private func loadInvitePreview() async {
        guard invitePreview == nil, joinedTrip == nil else { return }

        // Load user's trips for conflict detection
        await tripService.listMyTrips()

        do {
            invitePreview = try await tripService.fetchInvitePreview(
                inviteCode: inviteCode
            )
        } catch {
            // Keep fallback UI values when preview cannot be loaded.
        }
    }

    private func joinTrip() async {
        guard !isJoining else { return }
        isJoining = true
        errorMessage = nil

        do {
            let trip = try await tripService.joinTrip(inviteCode: inviteCode)
            joinedTrip = trip
            // Keep the avatar pinned while showing loading/success transition.
            try? await Task.sleep(for: .milliseconds(600))
            onJoined(trip.id)
        } catch {
            isJoining = false
            errorMessage = String(localized: "Failed to join trip")
        }
    }
}

#Preview {
    TripInvitationView(inviteCode: "abc123")
        .environment(UserProfileService())
}

private struct InvitationDragPreview: View {
    let coverImageUrl: String?
    let avatarUrl: String?
    let isJoining: Bool
    let showingConflictAlert: Bool
    var onJoinTriggered: () -> Void = {}

    @State private var avatarDragOffset: CGFloat = 0
    @State private var hasTriggeredJoin = false
    @State private var dragHapticMilestone = 0
    private let maxDragDistance: CGFloat = 303.5
    private let maxAvatarRotation: CGFloat = 90
    private let basePillHeight: CGFloat = 310
    private let minPillHeight: CGFloat = 60

    init(
        coverImageUrl: String? = nil,
        avatarUrl: String? = nil,
        isJoining: Bool = false,
        showingConflictAlert: Bool = false,
        onJoinTriggered: @escaping () -> Void = {}
    ) {
        self.coverImageUrl = coverImageUrl
        self.avatarUrl = avatarUrl
        self.isJoining = isJoining
        self.showingConflictAlert = showingConflictAlert
        self.onJoinTriggered = onJoinTriggered
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(width: 100, height: basePillHeight)
                .overlay(alignment: .bottom) {
                    TopRoundedPill()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.84, green: 0.93, blue: 1.0)
                                        .opacity(
                                            0.25
                                        ),
                                    Color(red: 0.58, green: 0.82, blue: 1.0),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 100, height: topPillHeight)
                }
                .zIndex(0)

            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Constants.OnSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(.black.opacity(0.15), lineWidth: 0.733)
                )
                .shadow(
                    color: .black.opacity(0.15),
                    radius: 23.463,
                    x: 0,
                    y: 2.933
                )
                .frame(width: 120, height: 120)
                .offset(y: 245)
                .zIndex(3)

            previewPhoto

            if isJoining {
                ProgressView()
                    .tint(.white)
                    .padding(.top, 120)
                    .zIndex(2)
            } else {
                VStack(spacing: 20) {
                    ArrowIndicator(opacity: 0.3)
                    ArrowIndicator(opacity: 0.7)
                    ArrowIndicator(opacity: 1.0)
                }
                .padding(.top, 80)
                .zIndex(1)
            }

            previewAvatar
        }
        .frame(width: 120, height: 450)
        .onChange(of: isJoining) { oldValue, newValue in
            // Join failed: return avatar to start position and allow retry.
            guard oldValue, !newValue, hasTriggeredJoin else { return }
            hasTriggeredJoin = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                avatarDragOffset = 0
            }
        }
        .onChange(of: showingConflictAlert) { oldValue, newValue in
            // Conflict alert dismissed: return avatar to start position.
            guard oldValue, !newValue, hasTriggeredJoin else { return }
            hasTriggeredJoin = false
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                avatarDragOffset = 0
            }
        }
    }

    private var avatarDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !isJoining, !hasTriggeredJoin else { return }
                avatarDragOffset = min(
                    max(0, value.translation.height),
                    maxDragDistance
                )
                triggerDragMilestoneHaptics()
            }
            .onEnded { _ in
                guard !isJoining, !hasTriggeredJoin else { return }
                if dragProgress >= 0.95 {
                    hasTriggeredJoin = true
                    withAnimation(
                        .spring(response: 0.34, dampingFraction: 0.86)
                    ) {
                        avatarDragOffset = maxDragDistance
                    }
                    onJoinTriggered()
                    dragHapticMilestone = 0
                    return
                }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    avatarDragOffset = 0
                }
                dragHapticMilestone = 0
            }
    }

    private func triggerDragMilestoneHaptics() {
        let milestone: Int
        if dragProgress >= 0.95 {
            milestone = 3
        } else if dragProgress >= 0.66 {
            milestone = 2
        } else if dragProgress >= 0.33 {
            milestone = 1
        } else {
            milestone = 0
        }

        guard milestone > dragHapticMilestone else { return }
        for _ in dragHapticMilestone..<milestone {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        dragHapticMilestone = milestone
    }

    private var topPillHeight: CGFloat {
        max(minPillHeight, basePillHeight - avatarDragOffset)
    }

    private var dragProgress: CGFloat {
        guard maxDragDistance > 0 else { return 0 }
        return min(1, max(0, avatarDragOffset / maxDragDistance))
    }

    private var avatarRotationDegrees: Double {
        Double(dragProgress * maxAvatarRotation)
    }
}

private struct ArrowIndicator: View {
    let opacity: CGFloat

    var body: some View {
        DoubleChevronDownShape()
            .stroke(
                Constants.White.opacity(Double(opacity)),
                style: StrokeStyle(
                    lineWidth: 3,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: 32, height: 32)
    }
}

private struct DoubleChevronDownShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        addChevron(to: &path, in: rect, topYRatio: 0.18, midYRatio: 0.44)
        addChevron(to: &path, in: rect, topYRatio: 0.50, midYRatio: 0.78)
        return path
    }

    private func addChevron(
        to path: inout Path,
        in rect: CGRect,
        topYRatio: CGFloat,
        midYRatio: CGFloat
    ) {
        let leftX = rect.minX + (rect.width * 0.18)
        let rightX = rect.maxX - (rect.width * 0.18)
        let centerX = rect.midX
        let topY = rect.minY + (rect.height * topYRatio)
        let midY = rect.minY + (rect.height * midYRatio)

        path.move(to: CGPoint(x: leftX, y: topY))
        path.addLine(to: CGPoint(x: centerX, y: midY))
        path.addLine(to: CGPoint(x: rightX, y: topY))
    }
}

private struct MemberAvatarStrip: View {
    let members: [TripMemberDto]

    var body: some View {
        HStack(spacing: -9) {
            ForEach(members.prefix(3), id: \.id) { member in
                if let urlString = member.avatarUrl,
                    let url = URL(string: urlString)
                {
                    CachedRemoteImage(
                        url: url,
                        targetSize: CGSize(width: 17, height: 17)
                    ) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image("avatarPlaceholder")
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(width: 17, height: 17)
                    .clipShape(Circle())
                } else {
                    Image("avatarPlaceholder")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 17, height: 17)
                        .clipShape(Circle())
                }
            }
        }
    }
}

extension InvitationDragPreview {
    fileprivate var previewPhoto: some View {
        Group {
            if let urlString = coverImageUrl, let url = URL(string: urlString) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 120, height: 120)
                ) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image("defaultTripPlaceholder")
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Image("defaultTripPlaceholder")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 120, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.black.opacity(0.15), lineWidth: 0.733)
        )
        .shadow(color: .black.opacity(0.15), radius: 23.463, x: 0, y: 2.933)
        .offset(y: 253.5)
        .zIndex(4)
    }

    fileprivate var previewAvatar: some View {
        Group {
            if let avatarUrl, let url = URL(string: avatarUrl) {
                CachedRemoteImage(
                    url: url,
                    targetSize: CGSize(width: 100, height: 100)
                ) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image("avatarPlaceholder")
                        .resizable()
                        .scaledToFill()
                }
            } else {
                Image("avatarPlaceholder")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(
                    Color(red: 0.835, green: 0.886, blue: 1),
                    lineWidth: 4
                )
        )
        .shadow(
            color: Color(red: 0.153, green: 0.294, blue: 1).opacity(0.53),
            radius: 20.9,
            x: 0,
            y: 0
        )
        .rotationEffect(.degrees(avatarRotationDegrees), anchor: .center)
        .offset(y: -50 + avatarDragOffset)
        .gesture(avatarDragGesture)
        .zIndex(3.5)
    }
}

private struct TopRoundedPill: Shape {
    func path(in rect: CGRect) -> Path {
        let topRadius = min(50, min(rect.width / 2, rect.height / 2))
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius),
            radius: topRadius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
