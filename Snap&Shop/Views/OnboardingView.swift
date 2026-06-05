import SwiftUI

private struct OnboardingSlide {
    let title: String
    let body: String
    let icon: String
}

struct OnboardingView: View {
    var onComplete: () -> Void = { }

    @State private var currentPage = 0

    private let slides: [OnboardingSlide] = [
        OnboardingSlide(title: "Snap It", body: "Point your camera at any product — no barcode needed.", icon: "camera.fill"),
        OnboardingSlide(title: "Compare Prices", body: "See live prices from Amazon, Walmart, Best Buy, and more.", icon: "tag.fill"),
        OnboardingSlide(title: "Save Money", body: "Track price drops on favourites and never overpay again.", icon: "star.fill")
    ]

    var body: some View {
        ZStack {
            Color.Brand.background.ignoresSafeArea()

            VStack(spacing: 0) {
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

    private func slideView(_ slide: OnboardingSlide) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            iconCard(slide.icon)
            VStack(spacing: Spacing.sm) {
                Text(slide.title)
                    .font(Typography.title)
                    .foregroundStyle(Color.Brand.textPrimary)
                Text(slide.body)
                    .font(Typography.body)
                    .foregroundStyle(Color.Brand.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xl)
            }
            Spacer()
        }
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
