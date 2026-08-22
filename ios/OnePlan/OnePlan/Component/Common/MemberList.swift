//
//  MemberList.swift
//  OnePlan
//
//  Created by Codex on 27/2/26.
//

import SwiftUI

struct MemberListEntry: Identifiable {
    enum ActionStyle {
        case dark
        case disabled
    }

    let id: String
    let name: String
    let subtitleText: String
    let imageName: String
    let avatarUrl: String?
    let actionText: String
    let actionStyle: ActionStyle
    let showsAction: Bool
    let showsRemoveAction: Bool
    /// Shown beside the name when the member holds a role worth naming. Nil for
    /// an ordinary member, who gets no badge rather than one saying so.
    let roleText: String?
    /// Whether this row offers its role to be changed. Only the leader sees it.
    let showsRoleAction: Bool
    /// Label for the role-change action ("Make co-host" / "Remove as co-host").
    let roleActionTitle: String
    /// Host-only vault leave clearance ("Mark paid for leave").
    let clearVaultLeaveTitle: String?
    let isPro: Bool

    init(
        id: String = UUID().uuidString,
        name: String,
        subtitleText: String,
        imageName: String = "avatarPlaceholder",
        avatarUrl: String? = nil,
        actionText: String = "Chat",
        actionStyle: ActionStyle = .dark,
        showsAction: Bool = true,
        showsRemoveAction: Bool = false,
        roleText: String? = nil,
        showsRoleAction: Bool = false,
        roleActionTitle: String = "",
        clearVaultLeaveTitle: String? = nil,
        isPro: Bool = false
    ) {
        self.id = id
        self.name = name
        self.subtitleText = subtitleText
        self.imageName = imageName
        self.avatarUrl = avatarUrl
        self.actionText = actionText
        self.actionStyle = actionStyle
        self.showsAction = showsAction
        self.showsRemoveAction = showsRemoveAction
        self.roleText = roleText
        self.showsRoleAction = showsRoleAction
        self.roleActionTitle = roleActionTitle
        self.clearVaultLeaveTitle = clearVaultLeaveTitle
        self.isPro = isPro
    }

    init(from member: TripMemberDto) {
        self.id = "\(member.id)"
        self.name = member.displayName
        self.subtitleText = member.inviteStatus.value1.rawValue.capitalized
        self.imageName = "avatarPlaceholder"
        self.avatarUrl = member.avatarUrl
        self.actionText = "Chat"
        self.actionStyle = .dark
        self.showsAction = true
        self.showsRemoveAction = false
        self.roleText = nil
        self.showsRoleAction = false
        self.roleActionTitle = ""
        self.clearVaultLeaveTitle = nil
        self.isPro = false
    }
}

private struct MemberListItem: View {
    let entry: MemberListEntry
    let onActionTapped: ((MemberListEntry) -> Void)?
    let onRemoveTapped: ((MemberListEntry) -> Void)?
    let onRoleTapped: ((MemberListEntry) -> Void)?
    var onClearVaultLeaveTapped: ((MemberListEntry) -> Void)? = nil
    let onRowTapped: ((MemberListEntry) -> Void)?
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @State private var isRoleDialogPresented = false

    var body: some View {
        rowContent
            .contentShape(Rectangle())
            .onTapGesture { onRowTapped?(entry) }
    }

    private var rowContent: some View {
        HStack(alignment: .center, spacing: 12) {
            if entry.isPro {
                AvatarProPlaceholder(
                    size: imageSize,
                    imageUrl: entry.avatarUrl,
                    placeholderImageName: entry.imageName,
                    showBadge: true
                )
            } else {
                plainAvatar
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(
                            Font.beVietnamPro(titleFontSize, weight: .medium)
                        )
                        .foregroundColor(Constants.ContentB)
                        .lineLimit(1)

                    if let roleText = entry.roleText {
                        Text(roleText)
                            .font(Font.beVietnamPro(12, weight: .medium))
                            .foregroundColor(Constants.White)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Constants.BlueBase, in: Capsule())
                    }
                }

                Text(entry.subtitleText)
                    .font(Font.custom("Be Vietnam Pro", size: subtitleFontSize))
                    .foregroundColor(Constants.ContentM)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if entry.showsRoleAction {
                Button {
                    isRoleDialogPresented = true
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundColor(Constants.ContentM)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change role")
                // Anchored on this button so the sheet/popover sits above the
                // ellipsis instead of jumping to the top of TripDetailView.
                .confirmationDialog(
                    entry.name,
                    isPresented: $isRoleDialogPresented,
                    titleVisibility: .visible
                ) {
                    Button(entry.roleActionTitle) {
                        onRoleTapped?(entry)
                    }
                    if let clearTitle = entry.clearVaultLeaveTitle {
                        Button(clearTitle) {
                            onClearVaultLeaveTapped?(entry)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("A co-host can approve payments over the trip limit.")
                }
            }

            if entry.showsAction {
                Button {
                    guard entry.actionStyle != .disabled else { return }
                    onActionTapped?(entry)
                } label: {
                    Text(entry.actionText)
                        .font(Font.custom("Be Vietnam Pro", size: 14))
                        .foregroundColor(
                            entry.actionStyle == .disabled
                                ? Constants.ContentL
                                : Constants.White
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            entry.actionStyle == .disabled
                                ? Constants.Neutral200
                                : Constants.Black
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(entry.actionStyle == .disabled || onActionTapped == nil)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }

    @ViewBuilder
    private var plainAvatar: some View {
        if let urlString = entry.avatarUrl, let url = URL(string: urlString) {
            CachedRemoteImage(
                url: url,
                targetSize: CGSize(width: imageSize, height: imageSize)
            ) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(entry.imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .frame(width: imageSize, height: imageSize)
            .clipShape(Circle())
        } else {
            Image(entry.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: imageSize, height: imageSize)
                .clipShape(Circle())
        }
    }
}

private struct MemberListHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MemberListSizingContent: View {
    let entries: [MemberListEntry]
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                MemberListItem(
                    entry: entry,
                    onActionTapped: nil,
                    onRemoveTapped: nil,
                    onRoleTapped: nil,
                    onRowTapped: nil,
                    titleFontSize: titleFontSize,
                    subtitleFontSize: subtitleFontSize,
                    imageSize: imageSize,
                    horizontalPadding: horizontalPadding,
                    verticalPadding: verticalPadding
                )
            }
        }
    }
}

struct MemberList: View {
    let entries: [MemberListEntry]
    let onActionTapped: ((MemberListEntry) -> Void)?
    let onRemoveTapped: ((MemberListEntry) -> Void)?
    let onRoleTapped: ((MemberListEntry) -> Void)?
    var onClearVaultLeaveTapped: ((MemberListEntry) -> Void)? = nil
    let onRowTapped: ((MemberListEntry) -> Void)?
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let imageSize: CGFloat
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    @State private var contentHeight: CGFloat = 1

    init(
        entries: [MemberListEntry] = MemberList.defaultEntries,
        onActionTapped: ((MemberListEntry) -> Void)? = nil,
        onRemoveTapped: ((MemberListEntry) -> Void)? = nil,
        onRoleTapped: ((MemberListEntry) -> Void)? = nil,
        onClearVaultLeaveTapped: ((MemberListEntry) -> Void)? = nil,
        onRowTapped: ((MemberListEntry) -> Void)? = nil,
        titleFontSize: CGFloat = 14,
        subtitleFontSize: CGFloat = 12,
        imageSize: CGFloat = 48,
        horizontalPadding: CGFloat = 14,
        verticalPadding: CGFloat = 10
    ) {
        self.entries = entries
        self.onActionTapped = onActionTapped
        self.onRemoveTapped = onRemoveTapped
        self.onRoleTapped = onRoleTapped
        self.onClearVaultLeaveTapped = onClearVaultLeaveTapped
        self.onRowTapped = onRowTapped
        self.titleFontSize = titleFontSize
        self.subtitleFontSize = subtitleFontSize
        self.imageSize = imageSize
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    @_disfavoredOverload
    @available(*, deprecated, message: "Use imageSize, horizontalPadding, and verticalPadding")
    init(
        entries: [MemberListEntry] = MemberList.defaultEntries,
        onActionTapped: ((MemberListEntry) -> Void)? = nil,
        onRemoveTapped: ((MemberListEntry) -> Void)? = nil,
        onRoleTapped: ((MemberListEntry) -> Void)? = nil,
        onRowTapped: ((MemberListEntry) -> Void)? = nil,
        titleFontSize: CGFloat = 20,
        subtitleFontSize: CGFloat = 14,
        imageWidth: CGFloat = 56,
        imageHeight: CGFloat = 56,
        usesPadding: Bool = true
    ) {
        self.init(
            entries: entries,
            onActionTapped: onActionTapped,
            onRemoveTapped: onRemoveTapped,
            onRoleTapped: onRoleTapped,
            onRowTapped: onRowTapped,
            titleFontSize: titleFontSize,
            subtitleFontSize: subtitleFontSize,
            imageSize: imageWidth == imageHeight ? imageWidth : min(imageWidth, imageHeight),
            horizontalPadding: usesPadding ? 14 : 0,
            verticalPadding: usesPadding ? 10 : 0
        )
    }

    var body: some View {
        List(entries) { entry in
            MemberListItem(
                entry: entry,
                onActionTapped: onActionTapped,
                onRemoveTapped: onRemoveTapped,
                onRoleTapped: onRoleTapped,
                onClearVaultLeaveTapped: onClearVaultLeaveTapped,
                onRowTapped: onRowTapped,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
                imageSize: imageSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .environment(\.defaultMinListRowHeight, 1)
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .topLeading) {
            MemberListSizingContent(
                entries: entries,
                titleFontSize: titleFontSize,
                subtitleFontSize: subtitleFontSize,
                imageSize: imageSize,
                horizontalPadding: horizontalPadding,
                verticalPadding: verticalPadding
            )
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .accessibilityHidden(true)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MemberListHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(MemberListHeightPreferenceKey.self) { height in
            contentHeight = max(height, 1)
        }
        .frame(height: contentHeight)
        .background(Constants.Surface)
        .cornerRadius(24)
    }
}

private extension MemberList {
    static let defaultEntries: [MemberListEntry] = [
        MemberListEntry(name: "Cattie", subtitleText: "12 mutual friends", imageName: "avatarPlaceholder"),
        MemberListEntry(name: "hmy", subtitleText: "4 mutual friends", imageName: "avatarPlaceholder"),
        MemberListEntry(name: "Thanh Danh", subtitleText: "2 mutual friends", imageName: "avatarPlaceholder"),
        MemberListEntry(name: "Shin", subtitleText: "2 mutual friends", imageName: "avatarPlaceholder"),
    ]
}

#Preview {
    MemberList()
        .padding()
        .background(Constants.Background)
}
