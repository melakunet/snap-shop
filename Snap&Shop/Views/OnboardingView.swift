import SwiftUI

private enum BulletTint { case accent, success }

private struct BulletItem {
    let icon: String
    let text: String
    let tint: BulletTint
    var dividerAbove: Bool = false
}

private struct OnboardingSlide {
    let title: String
    let body: String
    let icon: String
    var bullets: [BulletItem]? = nil
}

struct OnboardingView: View {
    var onComplete: () -> Void = {}

    @State private var currentPage = 0

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(
            title: "Snap It",
            body: "Point your camera at any product — no barcode needed. Compare live prices from Amazon, Walmart, Best Buy, and more in seconds.",
            icon: "camera.fill"
        ),
        OnboardingSlide(
            title: "Two Ways to Scan",
            body: "Precision captures one sharp photo for everyday items. Deep pans a video to fully identify complex or multi-sided products. Switch modes any time.",
            icon: "camera.aperture"
        ),
        OnboardingSlide(
            title: "Your Privacy",
            body: "Here's exactly what happens with your data.",
            icon: "lock.shield.fill",
            bullets: [
                BulletItem(
                    icon: "arrow.up.circle.fill",
                    text: "One compressed photo per Precision scan",
                    tint: .accent
                ),
                BulletItem(
                    icon: "arrow.up.circle.fill",
                    text: "Up to 8 keyframes per Deep scan — nothing else",
                    tint: .accent
                ),
                BulletItem(
                    icon: "checkmark.circle.fill",
                    text: "Your photo library — never accessed",
                    tint: .success,
                    dividerAbove: true
                ),
                BulletItem(
                    icon: "checkmark.circle.fill",
                    text: "Location & contacts — never collected",
                    tint: .success
                ),
                BulletItem(
                    icon: "checkmark.circle.fill",
                    text: "Your data is never sold",
                    tint: .success
                ),
            ]
        ),
    ]

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, Spacing.xl)

                TabView(selection: $currentPage) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        slideView(slide)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                pageIndicator
                    .padding(.bottom, Spacing.xl)

                actionButtons
                    .padding(.horizontal, Spacing.xl)
                    .padding(.bottom, Spacing.xxxl)
            }
        }
    }

    // MARK: — Slide layout

    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            iconCard(slide.icon)
            VStack(spacing: Spacing.sm) {
                Text(slide.title)
                    .font(Typography.title)
                    .foregroundStyle(Color.Brand.textPrimary)
                if let bullets = slide.bullets {
                    Text(slide.body)
                        .font(Typography.callout)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                    bulletList(bullets)
                        .padding(.top, Spacing.xs)
                } else {
                    Text(slide.body)
                        .font(Typography.body)
                        .foregroundStyle(Color.Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Spacing.xl)
                }
            }
            Spacer()
        }
    }

    private func bulletList(_ items: [BulletItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                if item.dividerAbove {
                    Divider()
                        .background(Color.Brand.border)
                        .padding(.vertical, Spacing.sm)
                }
                HStack(spacing: Spacing.sm) {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            item.tint == .accent ? Color.Brand.accent : Color.Brand.success
                        )
                        .frame(width: 20)
                    Text(item.text)
                        .font(Typography.caption)
                        .foregroundStyle(Color.Brand.textSecondary)
                    Spacer()
                }
                .padding(.vertical, Spacing.xs)
            }
        }
        .padding(.horizontal, Spacing.xl)
    }

    private func iconCard(_ icon: String) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.Brand.accent.opacity(0.18), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 110
                    )
                )
                .frame(width: 220, height: 220)

            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.Brand.surface)
                .frame(width: 160, height: 160)
                .shadow(color: Color.Brand.accent.opacity(0.14), radius: 28, y: 10)

            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundStyle(Color.Brand.accent)
                .symbolEffect(.bounce, value: currentPage)
        }
    }

    // MARK: — Page indicator

    private var pageIndicator: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(slides.indices, id: \.self) { index in
                Capsule()
                    .fill(index == currentPage ? Color.Brand.accent : Color.Brand.border)
                    .frame(width: index == currentPage ? 20 : 8, height: 8)
                    .animation(.spring(duration: 0.3), value: currentPage)
            }
        }
    }

    // MARK: — Action buttons

    private var actionButtons: some View {
        VStack(spacing: Spacing.md) {
            Button {
                if currentPage < slides.count - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
                } else {
                    onComplete()
                }
            } label: {
                Text(currentPage < slides.count - 1 ? "Next" : "Get Started")
                    .font(Typography.callout.weight(.semibold))
                    .foregroundStyle(Color.Brand.accentOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
                    .background(Color.Brand.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            if currentPage < slides.count - 1 {
                Button("Skip") { onComplete() }
                    .font(Typography.callout)
                    .foregroundStyle(Color.Brand.textSecondary)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
