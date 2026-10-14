import Foundation

/// 管理当前使用的 Excel 模板（内置模板或用户导入的模板），以及生成文件的保存位置。
enum TemplateStore {
    private static var supportDirectory: URL {
        let url = URL.applicationSupportDirectory.appending(path: "Templates", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static var customTemplateURL: URL {
        supportDirectory.appending(path: "custom.xlsx")
    }

    static var bundledTemplateURL: URL? {
        Bundle.main.url(forResource: "template", withExtension: "xlsx")
    }

    /// 叫场顺序表模板（打印时追加在分组表之后）。
    static func scheduleTemplate() -> Data? {
        Bundle.main.url(forResource: "schedule", withExtension: "xlsx").flatMap { try? Data(contentsOf: $0) }
    }

    /// 当前模板数据：优先使用导入的模板。
    static func currentTemplate(useCustom: Bool) throws -> Data {
        if useCustom, let data = try? Data(contentsOf: customTemplateURL) {
            return data
        }
        guard let url = bundledTemplateURL else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: url)
    }

    /// 导入用户选择的模板；先校验能否解析再保存。
    static func importTemplate(from url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        _ = try XLSXTemplateFiller.fill(template: data, groups: [])
        try data.write(to: customTemplateURL, options: .atomic)
    }

    static func removeCustomTemplate() {
        try? FileManager.default.removeItem(at: customTemplateURL)
    }

    /// 生成文件保存在 Documents/对阵表 下，可在「文件」App 中找到。
    static func exportURL(date: Date = .now) -> URL {
        let folder = URL.documentsDirectory.appending(path: "对阵表", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return folder.appending(path: "对阵表_\(formatter.string(from: date)).xlsx")
    }
}
