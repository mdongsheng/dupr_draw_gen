import Foundation

/// 一个分组（如 A 组）及其按顺序排列的队伍。
struct DrawGroup: Identifiable, Equatable {
    /// 分组字母，大写，如 "A"、"B"。
    let letter: String
    var teams: [String]

    var id: String { letter }
}

/// 解析结果中的提示信息。
struct DrawIssue: Identifiable, Equatable {
    enum Level { case warning, error }

    let level: Level
    let message: String

    var id: String { message }
}

/// 把用户粘贴的文本解析成分组。
///
/// 支持的写法：
/// ```
/// A组
/// 鹅蛋/Andy
/// 椰子/铁人
///
/// B组：
/// 1. 曹总/黄金杰
/// ```
/// 分组标题可写作 `A组`、`A 组：`、`Group A`、`组A`；队伍前的 `1.`、`1、`、`1)` 编号会被去掉。
enum DrawParser {
    private static let headerPatterns: [NSRegularExpression] = [
        #"^([A-Za-z])\s*组\s*[:：]?$"#,
        #"^(?:组|group)\s*([A-Za-z])\s*[:：]?$"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let numbering = try! NSRegularExpression(pattern: #"^\d{1,2}\s*[\.、\)）]\s*"#)

    static func parse(_ text: String) -> [DrawGroup] {
        var groups: [DrawGroup] = []
        var current: Int?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let letter = headerLetter(in: line) {
                if let existing = groups.firstIndex(where: { $0.letter == letter }) {
                    current = existing
                } else {
                    groups.append(DrawGroup(letter: letter, teams: []))
                    current = groups.count - 1
                }
                continue
            }

            guard let current else { continue } // 第一个分组标题之前的内容忽略
            groups[current].teams.append(normalizeTeam(line))
        }

        return groups.sorted { $0.letter < $1.letter }
    }

    /// 检查解析结果与模板容量是否匹配。
    static func issues(for groups: [DrawGroup], layout: TemplateLayout) -> [DrawIssue] {
        var issues: [DrawIssue] = []
        let supported = Set(layout.groups.map(\.letter))

        if groups.allSatisfy({ $0.teams.isEmpty }) {
            return [DrawIssue(level: .error, message: "还没有识别到任何队伍，请以「A组」「B组」作为分组标题。")]
        }

        for group in groups {
            guard supported.contains(group.letter) else {
                issues.append(DrawIssue(level: .warning, message: "模板不包含 \(group.letter) 组，该组将被忽略。"))
                continue
            }
            let capacity = layout.capacity(of: group.letter)
            if group.teams.count > capacity {
                issues.append(DrawIssue(level: .error, message: "\(group.letter) 组有 \(group.teams.count) 支队伍，模板最多 \(capacity) 支。"))
            } else if group.teams.count < capacity {
                issues.append(DrawIssue(level: .warning, message: "\(group.letter) 组只有 \(group.teams.count) 支队伍，空位将留白。"))
            }

            var seen = Set<String>()
            for team in group.teams where !seen.insert(team.lowercased()).inserted {
                issues.append(DrawIssue(level: .warning, message: "\(group.letter) 组中「\(team)」重复出现。"))
            }
        }

        for letter in layout.groups.map(\.letter) where !groups.contains(where: { $0.letter == letter }) {
            issues.append(DrawIssue(level: .warning, message: "未找到 \(letter) 组，对应位置将留白。"))
        }

        return issues
    }

    private static func headerLetter(in line: String) -> String? {
        let range = NSRange(line.startIndex..., in: line)
        for pattern in headerPatterns {
            if let match = pattern.firstMatch(in: line, range: range),
               let letterRange = Range(match.range(at: 1), in: line) {
                return line[letterRange].uppercased()
            }
        }
        return nil
    }

    private static func normalizeTeam(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        let stripped = numbering.stringByReplacingMatches(in: line, range: range, withTemplate: "")
        // 统一斜杠两侧的空格："A / B" -> "A/B"
        return stripped
            .replacingOccurrences(of: "／", with: "/")
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "/")
    }
}

extension DrawParser {
    static let sample = """
    A组
    鹅蛋/Andy
    椰子/铁人
    JC/ZZ
    冠野/黄梓航
    KL/seven
    Baymax Lin/YUNCHENG

    B组
    曹总/黄金杰
    CHAN CHUN YIN/陈嘉雯
    鹅蛋/Andy
    Issac/东
    Simon/Issac
    Zorn/Sun Yao Hung
    """
}
