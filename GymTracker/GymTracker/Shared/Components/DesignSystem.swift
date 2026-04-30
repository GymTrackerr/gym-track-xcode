//
//  DesignSystem.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-04-30.
//

import SwiftUI

struct AppBackgroundView: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground)

            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.1, blue: 0.1),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }
}

struct CardRowContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var cardFill: some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.08))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }
}

private struct CardRowContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        CardRowContainer {
            content
        }
    }
}

struct CardRowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.15 : 0.12), lineWidth: 1)
            )
    }

    private var cardFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.08))
        } else {
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

struct ConnectedCardSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CardRowBackground())
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ConnectedCardRow<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConnectedCardDivider: View {
    var leadingInset: CGFloat = 14

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

struct NavigableCardRow<Content: View, Destination: View>: View {
    let destination: Destination
    let content: Content

    init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder content: () -> Content
    ) {
        self.destination = destination()
        self.content = content()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            CardRowContainer {
                HStack(alignment: .top, spacing: 10) {
                    content
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        CardRowContainer {
            VStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
    }
}

struct FilterPill: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
            )
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .contentShape(Capsule(style: .continuous))
    }
}

extension View {
    func appBackground() -> some View {
        background(AppBackgroundView())
    }

    func cardRowContainerStyle() -> some View {
        modifier(CardRowContainerModifier())
    }

    func screenContentPadding() -> some View {
        frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    func dashboardContentPadding() -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    func editorSheetPresentation() -> some View {
        presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    func cardListRowStyle(
        top: CGFloat = 6,
        leading: CGFloat = 4,
        bottom: CGFloat = 6,
        trailing: CGFloat = 16,
        backgroundVerticalPadding: CGFloat = 4,
        backgroundHorizontalPadding: CGFloat = 4
    ) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
            .listRowSeparator(.hidden)
            .listRowBackground(
                CardRowBackground()
                    .padding(.vertical, backgroundVerticalPadding)
                    .padding(.horizontal, backgroundHorizontalPadding)
            )
    }
}
