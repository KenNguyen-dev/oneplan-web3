//
//  BottomSheet.swift
//  OnePlan
//
//  Created by Codex on 8/3/26.
//

import SwiftUI

/// Reusable bottom-sheet container.
/// - The backdrop fades in.
/// - The sheet slides up from the bottom.
/// - Content receives a dismiss closure to close the sheet with the same animation.
struct BottomSheet<Content: View>: View {
    @Binding var isPresented: Bool

    let sheetHeight: CGFloat
    let cornerRadius: CGFloat
    let backdropOpacity: Double
    let dismissOnBackdropTap: Bool
    let enablesPullToDismiss: Bool
    let pullToDismissThreshold: CGFloat
    let content: (_ dismiss: @escaping () -> Void) -> Content

    @State private var presentationProgress: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    init(
        isPresented: Binding<Bool>,
        sheetHeight: CGFloat = 520,
        cornerRadius: CGFloat = 32,
        backdropOpacity: Double = 0.36,
        dismissOnBackdropTap: Bool = true,
        enablesPullToDismiss: Bool = false,
        pullToDismissThreshold: CGFloat = 90,
        @ViewBuilder content: @escaping (_ dismiss: @escaping () -> Void) -> Content
    ) {
        _isPresented = isPresented
        self.sheetHeight = sheetHeight
        self.cornerRadius = cornerRadius
        self.backdropOpacity = backdropOpacity
        self.dismissOnBackdropTap = dismissOnBackdropTap
        self.enablesPullToDismiss = enablesPullToDismiss
        self.pullToDismissThreshold = pullToDismissThreshold
        self.content = content
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(presentationProgress)
                .ignoresSafeArea()
                .onTapGesture {
                    guard dismissOnBackdropTap else { return }
                    dismiss()
                }
                .animation(.easeOut(duration: 0.2), value: presentationProgress)

            VStack(spacing: 0) {
                content(dismiss)
            }
            .frame(maxWidth: .infinity)
            .frame(height: sheetHeight, alignment: .top)
            .background(Constants.Background)
            .clipShape(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .offset(y: (1 - presentationProgress) * (sheetHeight + 40) + dragOffset)
            .overlay(alignment: .top) {
                if enablesPullToDismiss {
                    Color.clear
                        .frame(height: 48)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 8)
                                .onChanged { value in
                                    dragOffset = max(0, value.translation.height)
                                }
                                .onEnded { value in
                                    if value.translation.height > pullToDismissThreshold {
                                        dismiss()
                                    } else {
                                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                                            dragOffset = 0
                                        }
                                    }
                                }
                        )
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.9), value: presentationProgress)
        }
        .background(Color.clear)
        .onAppear {
            presentationProgress = 1
            dragOffset = 0
        }
    }

    private func dismiss() {
        presentationProgress = 0
        dragOffset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isPresented = false
        }
    }
}

#Preview {
    BottomSheet(isPresented: .constant(true)) { _ in
        VStack {
            Text("BottomSheet Placeholder")
                .font(.headline)
            Text("Put any custom UI here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
