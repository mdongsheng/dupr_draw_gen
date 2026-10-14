import UIKit

/// 把工作表中的若干区域渲染成 PDF，每个区域一页（A4 横向），按模板的样式绘制并居中缩放到页面。
enum XLSXPrintRenderer {
    /// A4 横向，单位：磅。
    static let pageBounds = CGRect(x: 0, y: 0, width: 842, height: 595)
    private static let margin: CGFloat = 30

    static func pdf(from xlsx: Data, ranges: [String]) throws -> Data {
        let workbook = try XLSXWorkbook(xlsx: xlsx)
        let pages = ranges.compactMap { CellRange($0) }
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds)
        return renderer.pdfData { context in
            for range in pages {
                context.beginPage()
                draw(range, of: workbook, in: pageBounds.insetBy(dx: margin, dy: margin), context: context.cgContext)
            }
        }
    }

    // MARK: Drawing

    private static func draw(_ range: CellRange, of workbook: XLSXWorkbook, in area: CGRect, context: CGContext) {
        // 每列 / 每行的起点
        var xs: [Int: CGFloat] = [:]
        var x: CGFloat = 0
        for column in range.start.column...range.end.column {
            xs[column] = x
            x += workbook.columnWidthInPoints(column)
        }
        xs[range.end.column + 1] = x

        var ys: [Int: CGFloat] = [:]
        var y: CGFloat = 0
        for row in range.start.row...range.end.row {
            ys[row] = y
            y += workbook.rowHeightInPoints(row)
        }
        ys[range.end.row + 1] = y

        let scale = min(area.width / x, area.height / y, 1.6)
        let origin = CGPoint(x: area.midX - x * scale / 2, y: area.midY - y * scale / 2)

        func rect(from start: CellRef, to end: CellRef) -> CGRect {
            let minX = xs[start.column] ?? 0, maxX = xs[end.column + 1] ?? x
            let minY = ys[start.row] ?? 0, maxY = ys[end.row + 1] ?? y
            return CGRect(x: origin.x + minX * scale, y: origin.y + minY * scale,
                          width: (maxX - minX) * scale, height: (maxY - minY) * scale)
        }

        // 合并单元格：左上角单元格占据整个区域，其余被覆盖的单元格跳过
        var mergedRects: [CellRef: CGRect] = [:]
        var covered = Set<CellRef>()
        for merge in workbook.merges where range.contains(merge.start) {
            let end = CellRef(row: min(merge.end.row, range.end.row), column: min(merge.end.column, range.end.column))
            mergedRects[merge.start] = rect(from: merge.start, to: end)
            for row in merge.start.row...end.row {
                for column in merge.start.column...end.column where !(row == merge.start.row && column == merge.start.column) {
                    covered.insert(CellRef(row: row, column: column))
                }
            }
        }

        var items: [(rect: CGRect, format: XLSXWorkbook.Format, text: String)] = []
        for row in range.start.row...range.end.row {
            for column in range.start.column...range.end.column {
                let ref = CellRef(row: row, column: column)
                guard !covered.contains(ref), workbook.cells[ref] != nil else { continue }
                let frame = mergedRects[ref] ?? rect(from: ref, to: ref)
                items.append((frame, workbook.format(of: ref), workbook.cells[ref]?.text ?? ""))
            }
        }

        // 先填充，再画文字，最后画边框，保证边框在最上层
        for item in items {
            guard let fill = item.format.fill else { continue }
            UIColor(rgb: fill).setFill()
            context.fill(item.rect)
        }
        for item in items where !item.text.isEmpty {
            drawText(item.text, format: item.format, in: item.rect, scale: scale)
        }
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(max(0.5, 0.75 * scale))
        for item in items {
            strokeBorder(item.format.border, of: item.rect, context: context)
        }
    }

    private static func drawText(_ text: String, format: XLSXWorkbook.Format, in rect: CGRect, scale: CGFloat) {
        let font = format.font
        var uiFont = UIFont.systemFont(ofSize: CGFloat(font.size) * scale, weight: font.bold ? .bold : .regular)
        if font.italic, let descriptor = uiFont.fontDescriptor.withSymbolicTraits(uiFont.fontDescriptor.symbolicTraits.union(.traitItalic)) {
            uiFont = UIFont(descriptor: descriptor, size: 0)
        }

        let paragraph = NSMutableParagraphStyle()
        switch format.horizontal {
        case "center", "centerContinuous": paragraph.alignment = .center
        case "right": paragraph.alignment = .right
        default: paragraph.alignment = .left
        }
        paragraph.lineBreakMode = format.wrap ? .byWordWrapping : .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: UIColor(rgb: font.color),
            .paragraphStyle: paragraph,
        ]

        let inset = 3 * scale
        var box = rect.insetBy(dx: inset, dy: inset * 0.5)
        let string = text as NSString
        let measured = string.boundingRect(
            with: CGSize(width: format.wrap ? box.width : .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )

        // 不换行且超宽时，像 Excel 一样向两侧溢出
        if !format.wrap, measured.width > box.width {
            let extra = measured.width - box.width
            switch paragraph.alignment {
            case .center: box = box.insetBy(dx: -extra / 2, dy: 0)
            case .right: box.origin.x -= extra; box.size.width += extra
            default: box.size.width += extra
            }
        }

        let height = min(ceil(measured.height), box.height)
        let originY: CGFloat
        switch format.vertical {
        case "top": originY = box.minY
        case "center": originY = box.midY - height / 2
        default: originY = box.maxY - height
        }
        string.draw(
            with: CGRect(x: box.minX, y: originY, width: box.width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine],
            attributes: attributes,
            context: nil
        )
    }

    private static func strokeBorder(_ border: XLSXWorkbook.Border, of rect: CGRect, context: CGContext) {
        var segments: [(CGPoint, CGPoint)] = []
        if border.top { segments.append((CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY))) }
        if border.bottom { segments.append((CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY))) }
        if border.left { segments.append((CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY))) }
        if border.right { segments.append((CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))) }
        if border.diagonalDown { segments.append((CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))) }
        if border.diagonalUp { segments.append((CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY))) }
        guard !segments.isEmpty else { return }

        for (start, end) in segments {
            context.move(to: start)
            context.addLine(to: end)
        }
        context.strokePath()
    }
}

private extension UIColor {
    convenience init(rgb color: RGBColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: 1)
    }
}
