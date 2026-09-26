/// CustomDisclosureGroup.swift

import SwiftUI

@MainActor
struct CustomDisclosureGroup<Label: View, Content: View>: View {
    @State private var isExpanded: Bool
    private let label: Label
    private let content: Content

    init(
        isExpanded: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self._isExpanded = State(initialValue: isExpanded)
        self.content = content()
        self.label = label()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Row - Clicking whole row toggles state
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .frame(width: 12, height: 12)

                    label
                        .foregroundColor(.primary)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.top, 8)
                .clipped()
                .transition(.opacity)
            }
        }
    }
}

// MARK: - String Initializer Support
extension CustomDisclosureGroup where Label == Text {
    init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            isExpanded: isExpanded,
            content: content,
            label: { Text(titleKey) }
        )
    }

    init<S: StringProtocol>(
        _ title: S,
        isExpanded: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            isExpanded: isExpanded,
            content: content,
            label: { Text(title) }
        )
    }
}
