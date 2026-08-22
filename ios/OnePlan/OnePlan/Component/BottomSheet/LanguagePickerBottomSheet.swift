import SwiftUI

/// Picks the app's display language. Mirrors `CurrencyPickerBottomSheet`.
/// The selection is applied via `AppLanguage.apply()` by the caller, which then
/// prompts the user to restart (iOS only switches the bundle language on launch).
struct LanguagePickerBottomSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedLanguage: AppLanguage

    @State private var pendingLanguage: AppLanguage = .current

    var body: some View {
        VStack(spacing: 12) {
            LanguagePickerToolbar(
                onDismiss: { dismiss() },
                onConfirm: {
                    selectedLanguage = pendingLanguage
                    dismiss()
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(AppLanguage.allCases) { language in
                        LanguageRow(
                            language: language,
                            isSelected: pendingLanguage == language,
                            onTap: { pendingLanguage = language }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Constants.Background)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onAppear {
            pendingLanguage = selectedLanguage
        }
    }
}

private struct LanguagePickerToolbar: View {
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 9.8) {
            Color.clear
                .frame(width: 35.2, height: 15.6)

            HStack(alignment: .center) {
                Button(action: onDismiss) {
                    ZStack {
                        Circle()
                            .fill(Constants.OnSurface)
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Constants.ContentM)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Language")
                    .font(Font.custom("Be Vietnam Pro", size: 18))
                    .tracking(-0.72)
                    .foregroundStyle(Constants.ContentB)

                Spacer()

                Button(action: onConfirm) {
                    ZStack {
                        Circle()
                            .fill(Constants.BlueBase)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 43, height: 43)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LanguageRow: View {
    let language: AppLanguage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                LanguageSelectionIndicator(isSelected: isSelected)

                Text(verbatim: language.flag)
                    .font(.system(size: 24))

                // Autonym — shown in the language's own name, not localized.
                Text(verbatim: language.displayName)
                    .font(Font.custom("Be Vietnam Pro", size: 16))
                    .tracking(-0.32)
                    .foregroundStyle(Constants.ContentB)
                    .lineLimit(1)

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Constants.Background)
            .clipShape(.rect(cornerRadius: 19))
        }
        .buttonStyle(.plain)
    }
}

private struct LanguageSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Constants.BlueBase : .clear)
                .overlay(
                    Circle()
                        .stroke(
                            isSelected ? Color.clear : Constants.ContentL,
                            lineWidth: 1.5
                        )
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            LanguagePickerBottomSheet(selectedLanguage: .constant(.english))
        }
}
