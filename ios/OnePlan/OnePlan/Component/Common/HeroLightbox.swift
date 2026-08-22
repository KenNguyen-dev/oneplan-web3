//
//  HeroLightbox.swift
//  OnePlan
//

import SwiftUI
import UIKit

protocol HeroLightboxItem: Hashable {
    var id: Int { get }
}

struct HeroLightboxConfig<Element: HeroLightboxItem> {
    var selectedItem: Element?
    var sourceLocation: CGRect = .zero
    var sourceScrollID: Int? = nil
    var showFullScreenCover: Bool = false
}

struct HeroLightboxDetailView<Data: RandomAccessCollection, Detail: View, Overlay: View>: View where Data.Element: HeroLightboxItem {
    @Binding var config: HeroLightboxConfig<Data.Element>
    var data: Data
    @ViewBuilder var detail: (Data.Element, Bool, CGSize, @escaping () -> Void) -> Detail
    @ViewBuilder var overlay: (Data.Element?, Bool, CGSize, @escaping () -> Void) -> Overlay

    @State private var isExpanded = false
    @State private var viewSize: CGSize = .zero
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        TabView(selection: $config.selectedItem) {
            ForEach(data, id: \.id) { item in
                let sourceFrame = config.sourceLocation

                detail(item, isExpanded, dragOffset, dismiss)
                    .frame(
                        width: isExpanded ? viewSize.width : sourceFrame.width,
                        height: isExpanded ? viewSize.height : sourceFrame.height
                    )
                    .clipped()
                    .offset(
                        x: isExpanded ? 0 : sourceFrame.minX,
                        y: isExpanded ? 0 : sourceFrame.minY
                    )
                    .offset(dragOffset)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: isExpanded ? .center : .topLeading
                    )
                    .tag(item)
                    .ignoresSafeArea()
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .contentShape(.rect)
        .background {
            HeroLightboxPanGesture { gesture in
                let state = gesture.state
                let translation = gesture.translation(in: gesture.view)

                if state == .began || state == .changed {
                    dragOffset = .init(width: translation.x, height: translation.y)
                } else {
                    if dragOffset.height > 50 {
                        dismiss()
                    } else {
                        withAnimation(animation.speed(1.2)) {
                            dragOffset = .zero
                        }
                    }
                }
            }
        }
        .overlay {
            overlay(config.selectedItem, isExpanded, dragOffset, dismiss)
                .compositingGroup()
                .opacity(interactiveOpacity)
                .opacity(isExpanded ? 1 : 0)
        }
        .presentationBackground {
            Rectangle()
                .fill(.black)
                .opacity(interactiveOpacity)
                .opacity(isExpanded ? 1 : 0)
        }
        .allowsHitTesting(isExpanded)
        .onGeometryChange(for: CGSize.self, of: { proxy in
            proxy.size
        }, action: { newValue in
            viewSize = newValue
        })
        .task {
            guard !isExpanded else { return }
            withAnimation(animation) {
                isExpanded = true
            }
        }
    }

    private func dismiss() {
        Task {
            withAnimation(animation.speed(1.2)) {
                dragOffset = .zero
                isExpanded = false
            }

            try? await Task.sleep(for: .seconds(0.35))
            withoutAnimation {
                config.showFullScreenCover = false
            }
        }
    }

    private var animation: Animation {
        .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: 0)
    }

    private var interactiveOpacity: CGFloat {
        let opacityY = abs(dragOffset.height) / (viewSize.height * 0.3)
        return isExpanded ? (1 - opacityY) : 0
    }
}

/// Hosts the pan-to-dismiss `UIPanGestureRecognizer` without `UIGestureRecognizerRepresentable`
/// (which is iOS 18+). A transparent, non-interactive anchor view is placed in the hierarchy,
/// and the recognizer is attached to that view's superview — an ancestor of the lightbox's
/// paging `TabView` — so gesture arbitration matches what SwiftUI's `.gesture()` provided.
/// The delegate logic (vertical-only begin + require-fail vs an inner scroll view at the top)
/// is preserved exactly. Deploys to iOS 17.2.
struct HeroLightboxPanGesture: UIViewRepresentable {
    var handle: (UIPanGestureRecognizer) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.handle = handle
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(handle: handle)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var handle: (UIPanGestureRecognizer) -> Void
        private let pan: UIPanGestureRecognizer

        init(handle: @escaping (UIPanGestureRecognizer) -> Void) {
            self.handle = handle
            self.pan = UIPanGestureRecognizer()
            super.init()
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            pan.addTarget(self, action: #selector(handlePan(_:)))
        }

        /// Attaches the recognizer to the **top-most ancestor** of the anchor (the
        /// view just below the `UIWindow` — i.e. the fullScreenCover's hosting
        /// view), once the anchor is in the hierarchy.
        ///
        /// The anchor lives in the lightbox's `.background`, and SwiftUI does NOT
        /// guarantee that a `.background` host's immediate `superview` is also an
        /// ancestor of the sibling paging `TabView`. Attaching to the immediate
        /// superview therefore left the recognizer on a view that never saw the
        /// pan touches over the image → pan-to-dismiss silently died (the only way
        /// out of the MarketPlanSection lightbox, which has no close button). The
        /// original `.gesture()`-based `UIGestureRecognizerRepresentable` attached
        /// to the TabView's backing view (a guaranteed ancestor); walking to the
        /// top-most view restores that coverage on iOS 17.2. Delegate arbitration
        /// (vertical-only begin + require-fail vs the horizontal pager) is
        /// unchanged, so paging is unaffected.
        func attach(to anchor: UIView) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var target: UIView?
                var candidate: UIView? = anchor.superview
                while let next = candidate, !(next is UIWindow) {
                    target = next
                    candidate = next.superview
                }
                guard let target, self.pan.view !== target else { return }
                self.pan.view?.removeGestureRecognizer(self.pan)
                target.addGestureRecognizer(self.pan)
            }
        }

        func detach() {
            pan.view?.removeGestureRecognizer(pan)
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            handle(recognizer)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            if let scrollView = otherGestureRecognizer.view as? UIScrollView {
                let contentOffset = scrollView.contentOffset
                return contentOffset.y <= 0
            }

            return false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }

            let velocity = panGesture.velocity(in: panGesture.view)
            return velocity.y > abs(velocity.x)
        }
    }
}

extension View {
    func withoutAnimation(_ result: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            result()
        }
    }
}
