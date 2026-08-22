//
//  AppScreenContainer.swift
//  OnePlan
//
//  Created by Codex on 13/3/26.
//

import SwiftUI

/// Shared screen wrapper that applies the app-level background behind content.
struct AppScreenContainer<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Constants.Background.ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AppScreenContainer {
        ScrollView {
            Text("Preview")
                .padding()
        }
    }
}
