import LocalAuthentication
import SwiftUI

/// Optional Face ID / Touch ID / passcode lock, applied whenever the app goes to the background.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    @Published private(set) var isLocked: Bool
    @Published private(set) var isEnabled: Bool

    private static let enabledKey = "security.requireUnlock"
    private var isAuthenticating = false

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isLocked = enabled
    }

    /// Turning the lock on or off asks for authentication first, so it can't be
    /// changed by someone who just picked up an unlocked phone.
    func setEnabled(_ enabled: Bool) async {
        let reason = enabled ? "Turn on the PhilReader lock" : "Turn off the PhilReader lock"
        guard enabled != isEnabled, await authenticate(reason: reason, withoutPasscode: !enabled) else {
            objectWillChange.send()
            return
        }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
    }

    func lock() {
        if isEnabled { isLocked = true }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        if await authenticate(reason: "Unlock your library", withoutPasscode: true) {
            withAnimation(.easeOut(duration: 0.25)) { isLocked = false }
        }
    }

    /// `withoutPasscode` is the answer when the device has no passcode at all:
    /// the lock can't be turned on then, but it must never trap someone out.
    private func authenticate(reason: String, withoutPasscode: Bool) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return withoutPasscode }
        isAuthenticating = true
        defer { isAuthenticating = false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// "Face ID", "Touch ID", "Optic ID" or "Passcode", with a matching SF Symbol.
    static var method: (name: String, symbol: String) {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return ("Face ID", "faceid")
        case .touchID: return ("Touch ID", "touchid")
        default:
            if #available(iOS 17, *), context.biometryType == .opticID { return ("Optic ID", "opticid") }
            return ("Passcode", "lock.fill")
        }
    }
}

/// Covers the app while locked, and in the app switcher when the lock is on.
struct LockScreen: View {
    /// `false` just hides content (app switcher); `true` offers to unlock.
    let isLocked: Bool
    @EnvironmentObject private var appLock: AppLock

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 18) {
                AppGlyph(size: 84)
                Text("PhilReader")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                if isLocked {
                    Text("Your library is locked")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                    Button {
                        Task { await appLock.unlock() }
                    } label: {
                        Label("Unlock with \(AppLock.method.name)", systemImage: AppLock.method.symbol)
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(Color(red: 0.56, green: 0.13, blue: 0.42))
                    }
                    .padding(.top, 10)
                }
            }
        }
        .ignoresSafeArea()
        .task { if isLocked { await appLock.unlock() } }
    }
}

/// The app icon's coral-to-violet gradient.
struct BrandBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(red: 1.0, green: 0.48, blue: 0.36),
                                Color(red: 0.89, green: 0.20, blue: 0.41),
                                Color(red: 0.29, green: 0.13, blue: 0.55)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A small rendition of the app icon: gradient tile with a comic page and speech bubble.
struct AppGlyph: View {
    var size: CGFloat = 60

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(red: 1.0, green: 0.48, blue: 0.36),
                                        Color(red: 0.89, green: 0.20, blue: 0.41),
                                        Color(red: 0.29, green: 0.13, blue: 0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "rectangle.split.2x2.fill")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(-7))
                    Image(systemName: "ellipsis.bubble.fill")
                        .font(.system(size: size * 0.26, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color(red: 0.89, green: 0.20, blue: 0.41), .white)
                        .offset(x: size * 0.14, y: -size * 0.12)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.2), radius: size * 0.08, y: size * 0.04)
            .accessibilityHidden(true)
    }
}
