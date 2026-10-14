import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @AppStorage("draw.input") private var input = ""
    @AppStorage("template.useCustom") private var useCustomTemplate = false

    @FocusState private var editorFocused: Bool
    @State private var generated: GeneratedFile?
    @State private var errorMessage: String?
    @State private var importingTemplate = false
    @State private var successTick = 0

    private let layout = TemplateLayout.standard

    private var groups: [DrawGroup] { DrawParser.parse(input) }
    private var issues: [DrawIssue] { DrawParser.issues(for: groups, layout: layout) }
    private var canGenerate: Bool { !issues.contains { $0.level == .error } }
    private var teamCount: Int { groups.reduce(0) { $0 + $1.teams.count } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    inputSection
                    if !input.isEmpty && !issues.isEmpty { issueSection }
                    previewSection
                    templateSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
                .animation(.snappy, value: groups)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(backdrop)
            .safeAreaInset(edge: .bottom) { generateBar }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { editorFocused = false }
                }
            }
            .sheet(item: $generated) { file in
                ResultView(file: file)
            }
            .fileImporter(isPresented: $importingTemplate, allowedContentTypes: [.spreadsheetXLSX]) { result in
                importTemplate(result)
            }
            .alert("出错了", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .sensoryFeedback(.success, trigger: successTick)
        }
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                .accessibilityLabel("大美友约 Pickleball Club")

            VStack(alignment: .leading, spacing: 6) {
                Text("DUPR对阵表")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("粘贴分组名单，一键填入 Excel 模板。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "分组名单", trailing: teamCount > 0 ? "\(teamCount) 支队伍" : nil)
            Card {
                VStack(spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        if input.isEmpty {
                            Text("A组\n鹅蛋/Andy\n椰子/铁人\n…\n\nB组\n曹总/黄金杰\n…")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $input)
                            .focused($editorFocused)
                            .scrollContentBackground(.hidden)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .frame(minHeight: 220)
                    }
                    .font(.callout)

                    Divider()

                    HStack(spacing: 10) {
                        PasteButton(payloadType: String.self) { strings in
                            if let text = strings.first { input = text }
                        }
                        .buttonBorderShape(.capsule)
                        .labelStyle(.titleAndIcon)
                        .tint(Theme.color(for: "A"))

                        Button {
                            input = DrawParser.sample
                        } label: {
                            Label("示例", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)

                        Spacer()

                        if !input.isEmpty {
                            Button(role: .destructive) {
                                input = ""
                            } label: {
                                Label("清空", systemImage: "xmark")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.circle)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .controlSize(.small)
                    .font(.subheadline.weight(.medium))
                    .animation(.snappy, value: input.isEmpty)
                }
            }
        }
    }

    private var issueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(issues) { issue in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.level == .error ? Color.red : Color.orange)
                    Text(issue.message)
                        .font(.footnote)
                        .foregroundStyle(Color.primary.opacity(0.8))
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill((canGenerate ? Color.orange : Color.red).opacity(0.08))
        )
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "预览")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                ForEach(layout.groups, id: \.letter) { group in
                    GroupCard(
                        letter: group.letter,
                        teams: groups.first { $0.letter == group.letter }?.teams ?? [],
                        capacity: group.slots.count
                    )
                }
            }
        }
    }

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "模板")
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "tablecells")
                        .font(.title3)
                        .foregroundStyle(Theme.color(for: "A"))
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Theme.color(for: "A").opacity(0.12))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(useCustomTemplate ? "自定义模板" : "内置模板")
                            .font(.subheadline.weight(.semibold))
                        Text("A 组 C3:H3、B4:B9 · B 组 C12:H12、B13:B18")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Menu {
                        Button {
                            importingTemplate = true
                        } label: {
                            Label("导入模板…", systemImage: "square.and.arrow.down")
                        }
                        if useCustomTemplate {
                            Button(role: .destructive) {
                                TemplateStore.removeCustomTemplate()
                                useCustomTemplate = false
                            } label: {
                                Label("恢复内置模板", systemImage: "arrow.uturn.backward")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                    }
                    .tint(Color.primary)
                }
            }
        }
    }

    private var generateBar: some View {
        Button(action: generate) {
            HStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                Text("生成 Excel")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(canGenerate ? AnyShapeStyle(Theme.color(for: "A").gradient) : AnyShapeStyle(Color.gray.opacity(0.35)))
            )
            .shadow(color: Theme.color(for: "A").opacity(canGenerate ? 0.3 : 0), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canGenerate)
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var backdrop: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Theme.color(for: "A").opacity(0.12), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 360)
        }
        .ignoresSafeArea()
    }

    // MARK: Actions

    private func generate() {
        editorFocused = false
        do {
            let template = try TemplateStore.currentTemplate(useCustom: useCustomTemplate)
            let data = try XLSXTemplateFiller.fill(template: template, groups: groups, layout: layout)
            let excelURL = TemplateStore.exportURL()
            try data.write(to: excelURL, options: .atomic)

            let pdfURL = excelURL.deletingPathExtension().appendingPathExtension("pdf")
            try printPDF(from: data).write(to: pdfURL, options: .atomic)

            successTick += 1
            generated = GeneratedFile(excelURL: excelURL, pdfURL: pdfURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 打印页：A 组、B 组（来自生成的表格），再加固定的叫场顺序表（按 A1/B1 编号叫场），均为 A4 横向。
    private func printPDF(from data: Data) throws -> Data {
        var pages = XLSXPrintRenderer.pages(of: try XLSXWorkbook(xlsx: data), ranges: layout.printRanges)
        if let template = TemplateStore.scheduleTemplate() {
            let schedule = try XLSXWorkbook(xlsx: template)
            pages += schedule.pageRanges.map { XLSXPrintRenderer.Page(workbook: schedule, range: $0) }
        }
        return XLSXPrintRenderer.pdf(pages)
    }

    private func importTemplate(_ result: Result<URL, Error>) {
        do {
            try TemplateStore.importTemplate(from: result.get())
            useCustomTemplate = true
        } catch {
            errorMessage = "模板导入失败：\(error.localizedDescription)"
        }
    }
}

struct GeneratedFile: Identifiable {
    let excelURL: URL
    /// 打印用 PDF：每组一页，A4 横向。
    let pdfURL: URL
    var id: URL { excelURL }
}

private extension UTType {
    static let spreadsheetXLSX = UTType("org.openxmlformats.spreadsheetml.sheet") ?? .data
}

#Preview {
    ContentView()
}
