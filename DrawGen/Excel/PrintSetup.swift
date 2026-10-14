import Foundation

/// 设置生成文件的 Excel 打印参数：A4 横向、宽度缩放到一页、每个区域单独一页，
/// 这样在 Excel / Numbers 中直接打印也与应用内打印一致。尽力而为，模板结构不符时跳过。
enum PrintSetup {
    static func apply(_ ranges: [String], to entries: inout [ZipArchive.Entry], sheetIndex: Int) {
        let pages = ranges.compactMap { CellRange($0) }
        guard !pages.isEmpty, var sheet = String(data: entries[sheetIndex].data, encoding: .utf8) else { return }

        // 启用“调整为 1 页宽”（高度自动），各打印区域仍各占一页
        if sheet.contains(#"fitToPage="0""#) {
            sheet = sheet.replacingOccurrences(of: #"fitToPage="0""#, with: #"fitToPage="1""#)
        } else if !sheet.contains("fitToPage=") {
            let enabled = #"<pageSetUpPr fitToPage="1"/>"#
            if sheet.contains("<pageSetUpPr") {
                sheet = sheet.replacingOccurrences(of: "<pageSetUpPr", with: #"<pageSetUpPr fitToPage="1""#)
            } else if !replaceFirst(#"<sheetPr\b[^>]*/>"#, in: &sheet, with: { String($0.dropLast(2)) + ">" + enabled + "</sheetPr>" }),
                      !replaceFirst(#"</sheetPr>"#, in: &sheet, with: { enabled + $0 }) {
                replaceFirst(#"<worksheet\b[^>]*>"#, in: &sheet) { $0 + "<sheetPr>" + enabled + "</sheetPr>" }
            }
        }

        let setupXML = { (existing: String) -> String in
            var attributes = attributePairs(in: existing).filter {
                !["paperSize", "scale", "orientation", "fitToWidth", "fitToHeight"].contains($0.name)
            }
            attributes.insert(contentsOf: [
                (name: "paperSize", value: "9"),
                (name: "orientation", value: "landscape"),
                (name: "fitToWidth", value: "1"),
                (name: "fitToHeight", value: "0"),
            ], at: 0)
            return "<pageSetup " + attributes.map { #"\#($0.name)="\#($0.value)""# }.joined(separator: " ") + "/>"
        }
        if !replaceFirst(#"<pageSetup\b[^>]*/>"#, in: &sheet, with: setupXML) {
            replaceFirst(#"<pageMargins\b[^>]*/>"#, in: &sheet) { $0 + setupXML("<pageSetup/>") }
        }
        entries[sheetIndex].data = Data(sheet.utf8)

        setPrintArea(pages, in: &entries)
    }

    /// 打印区域设为多个区域（以逗号分隔），Excel 会把每个区域打印在单独的一页。
    private static func setPrintArea(_ pages: [CellRange], in entries: inout [ZipArchive.Entry]) {
        guard let index = entries.firstIndex(where: { $0.path == "xl/workbook.xml" }),
              var workbook = String(data: entries[index].data, encoding: .utf8),
              let sheetName = workbook.firstMatch(of: #/<sheet\b[^>]*\bname="([^"]*)"/#).map({ String($0.1) }) else { return }

        let quoted = sheetName.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } ? sheetName : "'\(sheetName.replacingOccurrences(of: "'", with: "''"))'"
        let area = pages.map { page in
            "\(quoted)!$\(columnName(page.start.column))$\(page.start.row):$\(columnName(page.end.column))$\(page.end.row)"
        }.joined(separator: ",")
        let definedName = #"<definedName name="_xlnm.Print_Area" localSheetId="0">\#(XML.escape(area))</definedName>"#

        if !replaceFirst(#"<definedName name="_xlnm\.Print_Area" localSheetId="0">.*?</definedName>"#, in: &workbook, with: { _ in definedName }),
           !replaceFirst(#"<definedNames>"#, in: &workbook, with: { $0 + definedName }) {
            replaceFirst(#"</sheets>"#, in: &workbook) { $0 + "<definedNames>" + definedName + "</definedNames>" }
        }
        entries[index].data = Data(workbook.utf8)
    }

    // MARK: Helpers

    private static func columnName(_ column: Int) -> String {
        var column = column
        var name = ""
        while column > 0 {
            let remainder = (column - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + remainder))) + name
            column = (column - 1) / 26
        }
        return name
    }

    private static func attributePairs(in element: String) -> [(name: String, value: String)] {
        element.matches(of: #/([\w:]+)="([^"]*)"/#).map { (name: String($0.1), value: String($0.2)) }
    }

    /// 用 transform(匹配文本) 替换第一个匹配；返回是否找到。
    @discardableResult
    private static func replaceFirst(_ pattern: String, in text: inout String, with transform: (String) -> String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return false }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return false }
        text = ns.replacingCharacters(in: match.range, with: transform(ns.substring(with: match.range)))
        return true
    }
}
