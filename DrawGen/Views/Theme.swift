import SwiftUI

enum Theme {
    static let cornerRadius: CGFloat = 22

    static func color(for letter: String) -> Color {
        switch letter {
        case "A": Color(red: 0.05, green: 0.56, blue: 0.47)  // 深青绿
        case "B": Color(red: 0.36, green: 0.36, blue: 0.86)  // 靛蓝
        case "C": Color(red: 0.88, green: 0.45, blue: 0.20)
        default: Color(red: 0.55, green: 0.35, blue: 0.75)
        }
    }
}

/// 统一的卡片容器。
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
    }
}

struct SectionLabel: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let trailing { Text(trailing) }
        }
        .font(.footnote.weight(.semibold))
        .textCase(.uppercase)
        .tracking(0.6)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
    }
}
