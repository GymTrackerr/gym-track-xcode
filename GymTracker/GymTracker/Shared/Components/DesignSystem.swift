//
//  DesignSystem.swift
//  GymTracker
//
//  Created by Daniel Kravec on 2026-04-30.
//

import SwiftUI

struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            backgroundBase

            LinearGradient(
                colors: gradientStops,
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: colorScheme == .dark ? 400 : 360)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .ignoresSafeArea()
    }

    private var backgroundBase: Color {
        colorScheme == .dark ? Color(.systemBackground) : Color(.systemGroupedBackground)
    }

    private var gradientStops: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.85, green: 0.1, blue: 0.1),
                Color.clear
            ]
        }

        return [
            Color(red: 0.86, green: 0.05, blue: 0.06).opacity(0.52),
            Color(red: 0.95, green: 0.18, blue: 0.16).opacity(0.24),
            Color(red: 1.0, green: 0.52, blue: 0.48).opacity(0.10),
            Color.clear
        ]
    }
}

struct CardRowContainer<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let isSelected: Bool
    let content: Content

    init(isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.isSelected = isSelected
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : cardBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.10),
                radius: 10,
                x: 0,
                y: 4
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }

    @ViewBuilder private var cardFill: some View {
        if colorScheme == .dark {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.08))
        } else {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.50))
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                }
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
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardFill)
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.025))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(cardBorder, lineWidth: 1)
            )
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.10),
                radius: 10,
                x: 0,
                y: 4
            )
    }

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }

    private var cardFill: AnyShapeStyle {
        if colorScheme == .dark {
            return AnyShapeStyle(Color.white.opacity(0.08))
        } else {
            return AnyShapeStyle(.regularMaterial)
        }
    }
}

private struct AdaptiveRoundedSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceFill)
                    .overlay {
                        if colorScheme == .light {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Color.white.opacity(0.30))
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(surfaceBorder, lineWidth: 1)
            }
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.10),
                radius: 10,
                x: 0,
                y: 4
            )
    }

    private var surfaceFill: AnyShapeStyle {
        colorScheme == .dark ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(.regularMaterial)
    }

    private var surfaceBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
    }
}

private struct AdaptiveCapsuleSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                Capsule(style: .continuous)
                    .fill(surfaceFill)
                    .overlay {
                        if colorScheme == .light {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.30))
                        }
                    }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(surfaceBorder, lineWidth: 1)
            }
            .shadow(
                color: colorScheme == .dark ? Color.clear : Color.black.opacity(0.10),
                radius: 8,
                x: 0,
                y: 3
            )
    }

    private var surfaceFill: AnyShapeStyle {
        colorScheme == .dark ? AnyShapeStyle(Color.white.opacity(0.08)) : AnyShapeStyle(.regularMaterial)
    }

    private var surfaceBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)
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

    func adaptiveCardSurface(cornerRadius: CGFloat = 16) -> some View {
        modifier(AdaptiveRoundedSurfaceModifier(cornerRadius: cornerRadius))
    }

    func adaptiveCapsuleSurface() -> some View {
        modifier(AdaptiveCapsuleSurfaceModifier())
    }

    func screenContentPadding() -> some View {
        frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    func screenListContentFrame() -> some View {
        frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 6)
            .contentMargins(.top, 12, for: .scrollContent)
            .contentMargins(.bottom, 12, for: .scrollContent)
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
        backgroundHorizontalPadding: CGFloat = 10
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
