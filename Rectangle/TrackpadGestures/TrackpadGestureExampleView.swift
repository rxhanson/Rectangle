import SwiftUI

/// An illustration only: it never sends gestures or moves application windows.
struct TrackpadGestureExampleView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var windowFrame = CGRect(x: 0.23, y: 0.22, width: 0.54, height: 0.60)
    @State private var windowOpacity = 1.0
    @State private var contactOffset = CGSize.zero
    @State private var contactOpacity = 0.65

    private let contacts: [(CGFloat, CGFloat, CGFloat)] = [
        (0, 13, 11), (20, 1, 12), (41, 5, 12), (61, 23, 10)
    ]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Swipe to arrange windows")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
            }
            desktop
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
                ZStack(alignment: .topLeading) {
                    ForEach(contacts.indices, id: \.self) { index in
                        let contact = contacts[index]
                        Circle().fill(.secondary)
                            .frame(width: contact.2, height: contact.2)
                            .offset(x: contact.0, y: contact.1)
                    }
                }
                .frame(width: 76, height: 37, alignment: .topLeading)
                .offset(contactOffset)
                .opacity(contactOpacity)
            }
            .frame(width: 156, height: 98)
            .padding(.vertical, 2)
            .accessibilityHidden(true)
        }
        .padding(20)
        .frame(width: 440)
        // SwiftUI cancels this finite sequence when the popover is dismissed.
        .task(id: reduceMotion) { await demonstrate() }
    }

    private var desktop: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 0.20, green: 0.24, blue: 0.33), Color(red: 0.20, green: 0.29, blue: 0.27)]
                            : [Color(red: 0.88, green: 0.90, blue: 0.95), Color(red: 0.82, green: 0.89, blue: 0.87)],
                        startPoint: .topTrailing, endPoint: .bottomLeading))
                HStack(spacing: 4) {
                    ForEach(0..<4) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 3 ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.15))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .position(x: geometry.size.width / 2, y: geometry.size.height - 12)
                exampleWindow
                    .frame(width: geometry.size.width * windowFrame.width,
                           height: geometry.size.height * windowFrame.height)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                    .opacity(windowOpacity)
                    .offset(x: geometry.size.width * windowFrame.minX,
                            y: geometry.size.height * windowFrame.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .frame(height: 225)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Four-finger gestures: swipe left or right to snap a window, up to maximize, and down to minimize.")
    }

    private var exampleWindow: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle().fill(.secondary.opacity(0.45)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 7).frame(height: 17)
            .background(.primary.opacity(0.025))
            GeometryReader { geometry in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.035))
                        .frame(width: max(0, geometry.size.width * 0.23))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<4) { index in
                            Capsule()
                                .fill(index == 0 ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.12))
                                .frame(width: max(0, geometry.size.width * (index == 0 ? 0.32 : 0.52)), height: 4)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(9)
        }
        .clipped()
    }

    @MainActor private func demonstrate() async {
        windowFrame = CGRect(x: 0.23, y: 0.22, width: 0.54, height: 0.60)
        windowOpacity = 1
        contactOffset = .zero
        contactOpacity = 0.65
        guard !reduceMotion else { return }
        let steps: [(CGRect, CGSize)] = [
            (CGRect(x: 0.02, y: 0.08, width: 0.47, height: 0.81), CGSize(width: -22, height: 0)),
            (CGRect(x: 0.51, y: 0.08, width: 0.47, height: 0.81), CGSize(width: 22, height: 0)),
            (CGRect(x: 0.02, y: 0.08, width: 0.96, height: 0.81), CGSize(width: 0, height: -17)),
            (CGRect(x: 0.56, y: 0.92, width: 0.02, height: 0.02), CGSize(width: 0, height: 17))
        ]
        do {
            try await Task.sleep(for: .milliseconds(250))
            for (index, step) in steps.enumerated() {
                contactOffset = .zero
                contactOpacity = 0
                withAnimation(.easeOut(duration: 0.25)) { contactOpacity = 0.9 }
                try await Task.sleep(for: .milliseconds(250))
                withAnimation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.70)) {
                    contactOffset = step.1
                }
                try await Task.sleep(for: .milliseconds(187))
                withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.725)) {
                    windowFrame = step.0
                    windowOpacity = index == 3 ? 0 : 1
                }
                try await Task.sleep(for: .milliseconds(513))
                withAnimation(.easeOut(duration: 0.30)) { contactOpacity = 0 }
                try await Task.sleep(for: .milliseconds(1050))
            }
            contactOffset = .zero
            withAnimation(.easeOut(duration: 0.20)) { contactOpacity = 0.65 }
        } catch is CancellationError {
            // Dismissal or a Reduce Motion change stops pending steps immediately.
        } catch { }
    }
}
