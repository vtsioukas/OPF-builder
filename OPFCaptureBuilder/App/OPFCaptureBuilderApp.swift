//
//  OPFCaptureBuilderApp.swift
//  OPFCaptureBuilder
//
//  Native SwiftUI application entry point. No analytics, no advertising, no tracking,
//  no cloud services, no user accounts.
//

import SwiftUI

@main
struct OPFCaptureBuilderApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.hasCompletedOnboarding {
                ProjectListView()
            } else {
                WelcomeView()
            }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BannerView(message: banner)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: model.banner)
        .onAppear { model.store.load() }
    }
}

private struct BannerView: View {
    @EnvironmentObject private var model: AppModel
    let message: BannerMessage

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .accessibilityHidden(true)
            Text(message.text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(background)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal)
        .shadow(radius: 4, y: 2)
        .onTapGesture { model.banner = nil }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message.text)
    }

    private var iconName: String {
        switch message.kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private var background: Color {
        switch message.kind {
        case .info: return AppTheme.accent
        case .success: return AppTheme.success
        case .error: return AppTheme.danger
        }
    }
}
