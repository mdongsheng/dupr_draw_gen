import SwiftUI

/// 单个分组的预览卡片：显示每个位置（A1、A2…）将写入的队伍。
struct GroupCard: View {
    let letter: String
    let teams: [String]
    let capacity: Int

    private var tint: Color { Theme.color(for: letter) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                VStack(spacing: 0) {
                    ForEach(0..<capacity, id: \.self) { index in
                        row(index: index)
                        if index < capacity - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(letter)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(tint.gradient)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("\(letter) 组")
                    .font(.headline)
                Text("循环赛")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(min(teams.count, capacity)) / \(capacity)")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(teams.count == capacity ? tint : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(teams.count == capacity ? 0.12 : 0.06)))
                .contentTransition(.numericText())
        }
    }

    private func row(index: Int) -> some View {
        let team = index < teams.count ? teams[index] : nil

        return HStack(spacing: 14) {
            Text("\(letter)\(index + 1)")
                .font(.system(.footnote, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(team == nil ? Color.secondary : tint)
                .frame(width: 38, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(team == nil ? 0.05 : 0.12))
                )

            if let team {
                TeamName(team: team)
            } else {
                Text("待定")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

/// 把 “鹅蛋/Andy” 显示为 “鹅蛋 / Andy”，斜杠弱化。
private struct TeamName: View {
    let team: String

    var body: some View {
        let players = team.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        players.enumerated().reduce(Text("")) { text, element in
            let name = Text(element.element).foregroundStyle(.primary)
            return element.offset == 0 ? name : text + Text("  /  ").foregroundStyle(.tertiary) + name
        }
        .font(.subheadline.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

#Preview {
    GroupCard(letter: "A", teams: ["鹅蛋/Andy", "椰子/铁人", "JC/ZZ"], capacity: 6)
        .padding()
        .background(Color(.systemGroupedBackground))
}
