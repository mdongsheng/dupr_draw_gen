import Foundation

/// 描述模板中每个分组的队名应写入哪些单元格。
///
/// 内置模板（template.xlsx）的布局：
/// - A 组：第 3 行 C~H 列为横向表头，B 列第 4~9 行为纵向表头，均填 A1~A6 的队名；
/// - B 组：第 12 行 C~H 列，B 列第 13~18 行，填 B1~B6 的队名。
struct TemplateLayout {
    struct Group {
        let letter: String
        /// slots[i] 为第 i+1 支队伍需要写入的所有单元格。
        let slots: [[String]]
    }

    let groups: [Group]

    func capacity(of letter: String) -> Int {
        groups.first { $0.letter == letter }?.slots.count ?? 0
    }

    static let standard = TemplateLayout(groups: [
        roundRobin(letter: "A", headerRow: 3, firstSideRow: 4),
        roundRobin(letter: "B", headerRow: 12, firstSideRow: 13),
    ])

    /// 循环赛交叉表：横向表头从 C 列开始，纵向表头在 B 列。
    private static func roundRobin(letter: String, headerRow: Int, firstSideRow: Int, size: Int = 6) -> Group {
        let columns = ["C", "D", "E", "F", "G", "H", "I", "J"]
        let slots = (0..<size).map { i in
            ["\(columns[i])\(headerRow)", "B\(firstSideRow + i)"]
        }
        return Group(letter: letter, slots: slots)
    }
}

/// 把分组写入 xlsx 模板，保留模板中所有样式、合并单元格与其他内容。
enum XLSXTemplateFiller {
    enum Failure: LocalizedError {
        case missingWorksheet
        case missingCell(String)
        case invalidXML(String)

        var errorDescription: String? {
            switch self {
            case .missingWorksheet: "模板中找不到工作表。"
            case .missingCell(let ref): "模板中缺少单元格 \(ref)。"
            case .invalidXML(let path): "模板中的 \(path) 无法解析。"
            }
        }
    }

    static func fill(template: Data, groups: [DrawGroup], layout: TemplateLayout = .standard) throws -> Data {
        var entries = try ZipArchive.read(template)

        guard let sheetIndex = worksheetIndex(in: entries) else { throw Failure.missingWorksheet }
        guard var sheet = String(data: entries[sheetIndex].data, encoding: .utf8) else {
            throw Failure.invalidXML(entries[sheetIndex].path)
        }

        // 计算每个单元格的目标文本
        var values: [(cell: String, text: String)] = []
        for layoutGroup in layout.groups {
            let teams = groups.first { $0.letter == layoutGroup.letter }?.teams ?? []
            for (index, cells) in layoutGroup.slots.enumerated() {
                let text = index < teams.count ? teams[index] : ""
                for cell in cells { values.append((cell, text)) }
            }
        }

        let sharedIndex = entries.firstIndex { $0.path == "xl/sharedStrings.xml" }
        var sharedStrings = sharedIndex.flatMap { String(data: entries[$0].data, encoding: .utf8) }

        for (cell, text) in values {
            let replacement: CellValue
            if text.isEmpty {
                replacement = .empty
            } else if sharedStrings != nil {
                replacement = .shared(SharedStrings.index(of: text, in: &sharedStrings!))
            } else {
                replacement = .inline(text)
            }
            sheet = try replaceCell(cell, in: sheet, with: replacement)
        }

        entries[sheetIndex].data = Data(sheet.utf8)
        if let sharedIndex, let sharedStrings {
            entries[sharedIndex].data = Data(sharedStrings.utf8)
        }
        return ZipArchive.write(entries)
    }

    // MARK: Worksheet

    private static func worksheetIndex(in entries: [ZipArchive.Entry]) -> Int? {
        entries.firstIndex { $0.path == "xl/worksheets/sheet1.xml" }
            ?? entries.firstIndex { $0.path.hasPrefix("xl/worksheets/") && $0.path.hasSuffix(".xml") }
    }

    private enum CellValue {
        case empty
        case shared(Int)
        case inline(String)
    }

    private static func replaceCell(_ ref: String, in sheet: String, with value: CellValue) throws -> String {
        // 匹配 <c r="C3" .../> 或 <c r="C3" ...>...</c>
        let pattern = #"<c r="\#(ref)"(?=[\s/>])([^>]*?)(?:/>|>.*?</c>)"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let nsSheet = sheet as NSString
        guard let match = regex.firstMatch(in: sheet, range: NSRange(location: 0, length: nsSheet.length)) else {
            throw Failure.missingCell(ref)
        }

        let attributes = nsSheet.substring(with: match.range(at: 1))
        let style = attributes.firstMatch(of: #/\bs="(\d+)"/#).map { #" s="\#($0.1)""# } ?? ""

        let xml: String
        switch value {
        case .empty:
            xml = #"<c r="\#(ref)"\#(style)/>"#
        case .shared(let index):
            xml = #"<c r="\#(ref)"\#(style) t="s"><v>\#(index)</v></c>"#
        case .inline(let text):
            xml = #"<c r="\#(ref)"\#(style) t="inlineStr"><is><t xml:space="preserve">\#(XML.escape(text))</t></is></c>"#
        }
        return nsSheet.replacingCharacters(in: match.range, with: xml)
    }
}

// MARK: - Shared strings

private enum SharedStrings {
    /// 返回 text 在共享字符串表中的索引；不存在则追加。
    static func index(of text: String, in xml: inout String) -> Int {
        let escaped = XML.escape(text)
        let items = xml.matches(of: #/<si>(.*?)</si>|<si\s[^>]*>(.*?)</si>/#.dotMatchesNewlines())

        for (index, item) in items.enumerated() {
            let body = String(item.output.1 ?? item.output.2 ?? "")
            if plainText(of: body) == escaped { return index }
        }

        let newIndex = items.count
        let entry = #"<si><t xml:space="preserve">\#(escaped)</t></si>"#
        if let close = xml.range(of: "</sst>", options: .backwards) {
            xml.replaceSubrange(close, with: entry + "</sst>")
        }
        xml = updateAttribute("uniqueCount", in: xml) { _ in newIndex + 1 }
        xml = updateAttribute("count", in: xml) { $0 + 1 }
        return newIndex
    }

    /// 只认 <si><t ...>文本</t>…</si> 这种纯文本条目（富文本条目不参与复用）。
    private static func plainText(of body: String) -> String? {
        guard let match = body.firstMatch(of: #/^<t(?:\s[^>]*)?>(.*?)</t>(?:<phoneticPr[^>]*/>)?$/#.dotMatchesNewlines()) else {
            return nil
        }
        return String(match.output.1)
    }

    private static func updateAttribute(_ name: String, in xml: String, transform: (Int) -> Int) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(<sst\b[^>]*?\s\#(name)=")(\d+)(")"#) else { return xml }
        let nsXML = xml as NSString
        guard let match = regex.firstMatch(in: xml, range: NSRange(location: 0, length: nsXML.length)),
              let current = Int(nsXML.substring(with: match.range(at: 2))) else { return xml }
        return nsXML.replacingCharacters(in: match.range(at: 2), with: String(transform(current)))
    }
}

enum XML {
    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            case "\t", "\n", "\r": result.unicodeScalars.append(scalar)
            default:
                // 去掉 XML 1.0 不允许的控制字符
                if scalar.value >= 0x20 { result.unicodeScalars.append(scalar) }
            }
        }
        return result
    }
}
