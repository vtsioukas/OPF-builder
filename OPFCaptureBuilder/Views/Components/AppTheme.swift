//
//  AppTheme.swift
//  OPFCaptureBuilder
//
//  A small design system based on system colours and semantic fonts, so light mode, dark
//  mode, Dynamic Type and Increase Contrast are all honoured automatically.
//

import SwiftUI

enum AppTheme {
    static let accent = Color.accentColor
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
    static let neutralSurface = Color(.secondarySystemGroupedBackground)
    static let groupedBackground = Color(.systemGroupedBackground)
    static let cardCornerRadius: CGFloat = 16

    static func severityColor(_ severity: ValidationSeverity) -> Color {
        switch severity {
        case .error: return danger
        case .warning: return warning
        case .info: return accent
        }
    }

    static func severityIcon(_ severity: ValidationSeverity) -> String {
        switch severity {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

/// A reusable card container used across the app.
struct CardContainer<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage {
                        Image(systemName: systemImage).foregroundStyle(AppTheme.accent)
                    }
                }
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppTheme.neutralSurface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous))
    }
}

/// A labelled row for metadata inspection.
struct MetadataRow: View {
    let label: String
    let value: String
    var isAvailable: Bool = true

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(isAvailable ? .primary : .secondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(isAvailable ? value : "unavailable")")
    }
}

/// Formats byte counts for the UI.
enum ByteCountFormatterHelper {
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    static func string(_ bytes: Int) -> String { string(Int64(bytes)) }
}
