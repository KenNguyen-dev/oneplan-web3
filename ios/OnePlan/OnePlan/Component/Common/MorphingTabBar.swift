//
//  MorphingTabBar.swift
//  OnePlan
//
//  Originally created by Balaji Venkatesh (Kavsoft).
//  Adapted for OnePlan.
//

import SwiftUI
import UIKit

protocol MorphingTabProtocol: CaseIterable, Hashable {
    var symbolImage: String { get }
    var selectedSymbolImage: String { get }
    var title: String { get }
}

extension MorphingTabProtocol {
    var selectedSymbolImage: String { symbolImage + ".fill" }
}

struct MorphingTabBar<Tab: MorphingTabProtocol, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    @ViewBuilder var expandedContent: ExpandedContent
    /// View Properties
    @State private var viewWidth: CGFloat?
    var body: some View {
        ZStack {
            let allCases = Array(Tab.allCases)
            let symbols = allCases.map(\.symbolImage)
            let selectedSymbols = allCases.map(\.selectedSymbolImage)
            let titles = allCases.map(\.title)
            let selectedIndex = Binding {
                return symbols.firstIndex(of: activeTab.symbolImage) ?? 0
            } set: { index in
                activeTab = allCases[index]
            }

            if let viewWidth {
                let progress: CGFloat = isExpanded ? 1 : 0
                let labelSize: CGSize = CGSize(width: viewWidth, height: 58)
                let cornerRadius: CGFloat = labelSize.height / 2

                ExpandableGlassEffect(
                    alignment: .center, progress: progress, labelSize: labelSize,
                    cornerRadius: cornerRadius
                ) {
                    expandedContent
                } label: {
                    CustomTabBar(
                        symbols: symbols,
                        selectedSymbols: selectedSymbols,
                        titles: titles,
                        index: selectedIndex
                    )
                    .frame(height: 54)
                    .padding(.horizontal, 2)
                    .offset(y: -0.7)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: { newValue in
            viewWidth = newValue
        }
        .frame(height: viewWidth == nil ? 58 : nil)
    }
}

private struct CustomTabBar: UIViewRepresentable {
    var tint: Color = .gray.opacity(0.15)
    var symbols: [String]
    var selectedSymbols: [String]
    var titles: [String]
    @Binding var index: Int

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: symbols)
        control.selectedSegmentIndex = index
        control.selectedSegmentTintColor = UIColor(tint)
        updateImages(for: control, selectedIndex: index)
        context.coordinator.renderedIndex = index

        control.addTarget(
            context.coordinator, action: #selector(context.coordinator.didSelect(_:)),
            for: .valueChanged)

        if #available(iOS 26, *) {
            // iOS 26: keep the system Liquid Glass appearance + tab-switch animation.
            // Setting custom background images opts the control OUT of the system glass
            // rendering, so instead just fade the default background image views. On iOS 26
            // the per-segment icons live deeper in the hierarchy, so `dropLast()` leaves
            // them visible.
            DispatchQueue.main.async {
                for view in control.subviews.dropLast() where view is UIImageView {
                    view.alpha = 0
                }
            }
        } else {
            // iOS 18: the `subviews.dropLast()` hack hides the segment icons (flatter
            // internal hierarchy), so use documented transparency APIs instead. There is
            // no Liquid Glass on iOS 18 anyway, so opting out of the system appearance is
            // a non-issue here.
            control.backgroundColor = .clear
            let transparent = UIImage()
            control.setBackgroundImage(transparent, for: .normal, barMetrics: .default)
            control.setBackgroundImage(transparent, for: .highlighted, barMetrics: .default)
            control.setDividerImage(
                transparent,
                forLeftSegmentState: .normal,
                rightSegmentState: .normal,
                barMetrics: .default
            )
        }

        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        // Keep the coordinator's bindings current — the parent struct (and its
        // `index` binding) is a value copy captured at makeCoordinator time.
        context.coordinator.parent = self

        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }
        // `updateUIView` runs every frame while the enclosing Animatable glass
        // morph animates; re-rendering the 4 composite images each frame stalls
        // the main thread and drops touches. Only re-render when selection changes.
        if context.coordinator.renderedIndex != index {
            updateImages(for: uiView, selectedIndex: index)
            context.coordinator.renderedIndex = index
        }
    }

    private func updateImages(for control: UISegmentedControl, selectedIndex: Int) {
        for (i, symbol) in symbols.enumerated() {
            let isSelected = i == selectedIndex
            let iconName = isSelected ? selectedSymbols[i] : symbol
            let title = titles[i]
            let color = isSelected ? UIColor(Constants.BlueBase) : UIColor(Constants.ContentL)
            let targetIconHeight: CGFloat = 22

            guard let icon = resolvedIcon(named: iconName, color: color) else {
                continue
            }

            let font = UIFont(name: "BeVietnamPro-Regular", size: 13) ?? .systemFont(ofSize: 13)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let textSize = (title as NSString).size(withAttributes: attrs)
            let iconScale = targetIconHeight / max(icon.size.height, 1)
            let iconSize = CGSize(width: icon.size.width * iconScale, height: targetIconHeight)
            let spacing: CGFloat = 6
            let compositeWidth = max(iconSize.width, textSize.width, 54)
            let compositeHeight = iconSize.height + spacing + textSize.height
            let compositeSize = CGSize(width: compositeWidth, height: compositeHeight)

            let renderer = UIGraphicsImageRenderer(size: compositeSize)
            let composite = renderer.image { _ in
                let iconX = (compositeWidth - iconSize.width) / 2
                icon.draw(in: CGRect(origin: CGPoint(x: iconX, y: 0), size: iconSize))

                let textX = (compositeWidth - textSize.width) / 2
                (title as NSString).draw(
                    at: CGPoint(x: textX, y: iconSize.height + spacing), withAttributes: attrs)
            }

            control.setImage(composite.withRenderingMode(.alwaysOriginal), forSegmentAt: i)
        }
    }

    private func resolvedIcon(named name: String, color: UIColor) -> UIImage? {
        if let assetIcon = UIImage(named: name) {
            return assetIcon.withRenderingMode(.alwaysOriginal)
        }

        let configuration = UIImage.SymbolConfiguration(
            pointSize: 23,
            weight: .medium
        )
        guard
            let sfSymbol = UIImage(
                systemName: name,
                withConfiguration: configuration
            )
        else {
            return nil
        }

        return sfSymbol.withTintColor(color, renderingMode: .alwaysOriginal)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject {
        var parent: CustomTabBar
        /// Last index the composite segment images were rendered for.
        var renderedIndex: Int?
        private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()

        init(parent: CustomTabBar) {
            self.parent = parent
            selectionFeedbackGenerator.prepare()
        }

        @objc
        func didSelect(_ control: UISegmentedControl) {
            selectionFeedbackGenerator.selectionChanged()
            selectionFeedbackGenerator.prepare()
            parent.index = control.selectedSegmentIndex
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context)
        -> CGSize?
    {
        return proposal.replacingUnspecifiedDimensions()
    }
}
