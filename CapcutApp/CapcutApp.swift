import SwiftUI

@main
struct CapcutApp: App {
    @StateObject private var viewModel = AppViewModel()
    @State private var showsLaunchSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(viewModel: viewModel)

                if showsLaunchSplash {
                    LaunchSplashView()
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .task {
                guard showsLaunchSplash else { return }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.35)) {
                        showsLaunchSplash = false
                    }
                }
            }
        }
    }
}

private struct LaunchSplashView: View {
    @State private var isContentVisible = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.11),
                    Color(red: 0.10, green: 0.12, blue: 0.19),
                    Color(red: 0.17, green: 0.20, blue: 0.29)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color(red: 0.99, green: 0.51, blue: 0.17).opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 30)
                .offset(x: -110, y: -220)

            Circle()
                .fill(Color(red: 0.28, green: 0.54, blue: 0.97).opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 120, y: 230)

            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.00, green: 0.66, blue: 0.25),
                                    Color(red: 0.95, green: 0.34, blue: 0.14)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 108, height: 108)
                        .shadow(color: Color.black.opacity(0.22), radius: 18, y: 10)

                    Image(systemName: "film.stack.fill")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("FluxCut Studio")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 28)
            .opacity(isContentVisible ? 1 : 0.35)
            .scaleEffect(isContentVisible ? 1 : 0.96)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) {
                isContentVisible = true
            }
        }
    }

}
