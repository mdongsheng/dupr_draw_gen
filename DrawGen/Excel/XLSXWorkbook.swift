import Foundation

/// 单元格坐标（1 起）。
struct CellRef: Hashable {
    let row: Int
    let column: Int

    init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// 解析 "C3"、"$C$3"。
    init?(_ string: String) {
        var letters = 0
        var digits = ""
        for character in string where character != "$" {
            if let ascii = character.asciiValue, character.isLetter {
                letters = letters * 26 + Int(ascii & 0xDF) - 64
            } else if character.isNumber {
                digits.append(character)
            } else {
                return nil
            }
        }
        guard letters > 0, let row = Int(digits), row > 0 else { return nil }
        self.init(row: row, column: letters)
    }
}

/// 单元格区域，如 "A1:K9"。
struct CellRange {
    let start: CellRef
    let end: CellRef

    init?(_ string: String) {
        let parts = string.split(separator: ":").map(String.init)
        guard let first = parts.first.flatMap({ CellRef($0) }) else { return nil }
        let last = parts.count > 1 ? CellRef(parts[1]) : first
        guard let last else { return nil }
        start = CellRef(row: min(first.row, last.row), column: min(first.column, last.column))
        end = CellRef(row: max(first.row, last.row), column: max(first.column, last.column))
    }

    func contains(_ ref: CellRef) -> Bool {
        (start.row...end.row).contains(ref.row) && (start.column...end.column).contains(ref.column)
    }
}

struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    static let black = RGBColor(red: 0, green: 0, blue: 0)
    static let white = RGBColor(red: 1, green: 1, blue: 1)

    /// "FFRRGGBB" 或 "RRGGBB"
    init?(hex: String) {
        let digits = hex.count == 8 ? String(hex.dropFirst(2)) : hex
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
        red = Double((value >> 16) & 0xFF) / 255
        green = Double((value >> 8) & 0xFF) / 255
        blue = Double(value & 0xFF) / 255
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Excel 的 tint：在 HSL 空间调整亮度。
    func applying(tint: Double) -> RGBColor {
        guard tint != 0 else { return self }
        var (h, s, l) = hsl
        l = tint < 0 ? l * (1 + tint) : l * (1 - tint) + tint
        return RGBColor(hue: h, saturation: s, lightness: l)
    }

    private var hsl: (Double, Double, Double) {
        let maxValue = max(red, green, blue), minValue = min(red, green, blue)
        let l = (maxValue + minValue) / 2
        guard maxValue != minValue else { return (0, 0, l) }
        let d = maxValue - minValue
        let s = l > 0.5 ? d / (2 - maxValue - minValue) : d / (maxValue + minValue)
        var h: Double
        switch maxValue {
        case red: h = (green - blue) / d + (green < blue ? 6 : 0)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h /= 6
        return (h, s, l)
    }

    private init(hue h: Double, saturation s: Double, lightness l: Double) {
        guard s != 0 else {
            self.init(red: l, green: l, blue: l)
            return
        }
        func channel(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        self.init(red: channel(p, q, h + 1 / 3), green: channel(p, q, h), blue: channel(p, q, h - 1 / 3))
    }
}

/// 打印所需的工作表信息：单元格文本、样式、行高列宽、合并单元格。
struct XLSXWorkbook {
    struct Cell {
        let style: Int
        let text: String
    }

    struct Font {
        var size: Double = 11
        var bold = false
        var italic = false
        var color: RGBColor = .black
    }

    struct Border {
        var left = false
        var right = false
        var top = false
        var bottom = false
        var diagonalDown = false
        var diagonalUp = false
        var color: RGBColor = .black
    }

    struct Format {
        var font = Font()
        var fill: RGBColor?
        var border = Border()
        var horizontal: String?
        var vertical: String?
        var wrap = false
    }

    var cells: [CellRef: Cell] = [:]
    var formats: [Format] = [Format()]
    var columnWidths: [Int: Double] = [:]   // 字符宽度
    var defaultColumnWidth: Double = 8.43
    var rowHeights: [Int: Double] = [:]     // 磅
    var defaultRowHeight: Double = 15
    var merges: [CellRange] = []
    /// 工作簿中定义的打印区域（_xlnm.Print_Area），可能为空。
    var printAreas: [CellRange] = []

    /// 打印区域；未定义时返回包含所有单元格的范围。
    var pageRanges: [CellRange] {
        if !printAreas.isEmpty { return printAreas }
        let refs = cells.keys
        guard let maxRow = refs.map(\.row).max(), let maxColumn = refs.map(\.column).max(),
              let range = CellRange("A1:\(PrintSetup.columnName(maxColumn))\(maxRow)") else { return [] }
        return [range]
    }

    func format(of ref: CellRef) -> Format {
        guard let style = cells[ref]?.style, formats.indices.contains(style) else { return formats.first ?? Format() }
        return formats[style]
    }

    /// 列宽（磅）。Excel 列宽单位约为 7 像素/字符，1 像素 = 0.75 磅。
    func columnWidthInPoints(_ column: Int) -> Double {
        (columnWidths[column] ?? defaultColumnWidth) * 7 * 0.75
    }

    func rowHeightInPoints(_ row: Int) -> Double {
        rowHeights[row] ?? defaultRowHeight
    }

    // MARK: Loading

    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? { "无法读取生成的表格。" }
    }

    init(xlsx data: Data) throws {
        try self.init(entries: ZipArchive.read(data))
    }

    init(entries: [ZipArchive.Entry]) throws {
        func node(_ path: String) -> XMLNode? {
            entries.first { $0.path == path }.flatMap { XMLNode.parse($0.data) }
        }

        guard let sheetEntry = XLSXTemplateFiller.worksheetEntry(in: entries),
              let sheet = XMLNode.parse(sheetEntry.data) else { throw Failure.unreadable }

        let sharedStrings = node("xl/sharedStrings.xml").map(Self.sharedStrings) ?? []
        let theme = node("xl/theme/theme1.xml").map(Self.themeColors) ?? []
        if let styles = node("xl/styles.xml") {
            formats = Self.formats(from: styles, theme: theme)
        }

        if let format = sheet.child("sheetFormatPr") {
            if let height = format["defaultRowHeight"].flatMap(Double.init) { defaultRowHeight = height }
            if let width = format["defaultColWidth"].flatMap(Double.init) {
                defaultColumnWidth = width
            } else if let base = format["baseColWidth"].flatMap(Double.init) {
                defaultColumnWidth = base + 5.0 / 7
            }
        }

        for col in sheet.child("cols")?.children("col") ?? [] {
            guard let min = col["min"].flatMap(Int.init), let max = col["max"].flatMap(Int.init),
                  let width = col["width"].flatMap(Double.init), min <= max else { continue }
            for column in min...Swift.min(max, 256) { columnWidths[column] = width }
        }

        for row in sheet.child("sheetData")?.children("row") ?? [] {
            if let index = row["r"].flatMap(Int.init), let height = row["ht"].flatMap(Double.init) {
                rowHeights[index] = height
            }
            for c in row.children("c") {
                guard let ref = c["r"].flatMap({ CellRef($0) }) else { continue }
                let style = c["s"].flatMap(Int.init) ?? 0
                let value = c.child("v")?.text ?? ""
                let text: String
                switch c["t"] {
                case "s": text = Int(value).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
                case "inlineStr": text = c.child("is").map(Self.richText) ?? ""
                default: text = value
                }
                cells[ref] = Cell(style: style, text: text)
            }
        }

        if let workbook = node("xl/workbook.xml") {
            printAreas = Self.printAreas(in: workbook)
        }

        merges = (sheet.child("mergeCells")?.children("mergeCell") ?? []).compactMap { $0["ref"].flatMap { CellRange($0) } }
    }

    /// 读取第一个工作表的打印区域，如 "完整赛程!$A$1:$E$18" 或 "'Sheet 1'!$A$1:$K$9,'Sheet 1'!$A$10:$K$18"。
    private static func printAreas(in workbook: XMLNode) -> [CellRange] {
        let names = workbook.child("definedNames")?.children("definedName") ?? []
        guard let printArea = names.first(where: { $0["name"] == "_xlnm.Print_Area" && ($0["localSheetId"] ?? "0") == "0" }) else {
            return []
        }
        return printArea.text.split(separator: ",").compactMap { part in
            let reference = part.split(separator: "!").last.map(String.init) ?? String(part)
            return CellRange(reference)
        }
    }

    private static func sharedStrings(_ root: XMLNode) -> [String] {
        root.children("si").map(richText)
    }

    /// <si>/<is> 中的文本：直接的 <t> 或富文本 <r><t>，忽略拼音 <rPh>。
    private static func richText(_ node: XMLNode) -> String {
        node.children.reduce(into: "") { text, child in
            switch child.name {
            case "t": text += child.text
            case "r": text += child.child("t")?.text ?? ""
            default: break
            }
        }
    }

    /// 主题色按 Excel 的 theme 索引排列：lt1, dk1, lt2, dk2, accent1–6, hlink, folHlink。
    private static func themeColors(_ root: XMLNode) -> [RGBColor] {
        guard let scheme = root.child("themeElements")?.child("clrScheme") else { return [] }
        func color(_ name: String) -> RGBColor {
            guard let element = scheme.child(name)?.children.first else { return .black }
            return RGBColor(hex: element["val"] ?? "") ?? RGBColor(hex: element["lastClr"] ?? "") ?? .black
        }
        return ["lt1", "dk1", "lt2", "dk2", "accent1", "accent2", "accent3", "accent4", "accent5", "accent6", "hlink", "folHlink"]
            .map(color)
    }

    private static func color(_ node: XMLNode?, theme: [RGBColor]) -> RGBColor? {
        guard let node else { return nil }
        var base: RGBColor?
        if let rgb = node["rgb"] {
            base = RGBColor(hex: rgb)
        } else if let index = node["theme"].flatMap(Int.init), theme.indices.contains(index) {
            base = theme[index]
        } else if let indexed = node["indexed"].flatMap(Int.init) {
            base = indexed == 9 || indexed == 1 || indexed == 65 ? .white : .black
        } else if node["auto"] != nil {
            base = .black
        }
        let tint = node["tint"].flatMap(Double.init) ?? 0
        return base?.applying(tint: tint)
    }

    private static func formats(from styles: XMLNode, theme: [RGBColor]) -> [Format] {
        let fonts: [Font] = (styles.child("fonts")?.children("font") ?? []).map { node in
            var font = Font()
            if let size = node.child("sz")?["val"].flatMap(Double.init) { font.size = size }
            font.bold = node.child("b").map { $0["val"] != "0" } ?? false
            font.italic = node.child("i").map { $0["val"] != "0" } ?? false
            font.color = Self.color(node.child("color"), theme: theme) ?? .black
            return font
        }

        let fills: [RGBColor?] = (styles.child("fills")?.children("fill") ?? []).map { node in
            guard let pattern = node.child("patternFill"), pattern["patternType"] == "solid" else { return nil }
            return Self.color(pattern.child("fgColor"), theme: theme)
        }

        let borders: [Border] = (styles.child("borders")?.children("border") ?? []).map { node in
            func has(_ edge: String) -> Bool {
                guard let style = node.child(edge)?["style"] else { return false }
                return style != "none"
            }
            let diagonal = has("diagonal")
            let edgeColor = ["left", "right", "top", "bottom", "diagonal"].compactMap { edge -> RGBColor? in
                guard let element = node.child(edge), element["style"] != nil else { return nil }
                return Self.color(element.child("color"), theme: theme)
            }.first
            return Border(
                left: has("left"), right: has("right"), top: has("top"), bottom: has("bottom"),
                diagonalDown: diagonal && node["diagonalDown"] == "1",
                diagonalUp: diagonal && node["diagonalUp"] == "1",
                color: edgeColor ?? .black
            )
        }

        let xfs = styles.child("cellXfs")?.children("xf") ?? []
        guard !xfs.isEmpty else { return [Format()] }
        return xfs.map { xf in
            var format = Format()
            if let id = xf["fontId"].flatMap(Int.init), fonts.indices.contains(id) { format.font = fonts[id] }
            if let id = xf["fillId"].flatMap(Int.init), fills.indices.contains(id) { format.fill = fills[id] }
            if let id = xf["borderId"].flatMap(Int.init), borders.indices.contains(id) { format.border = borders[id] }
            if let alignment = xf.child("alignment") {
                format.horizontal = alignment["horizontal"]
                format.vertical = alignment["vertical"]
                format.wrap = alignment["wrapText"] == "1"
            }
            return format
        }
    }
}
