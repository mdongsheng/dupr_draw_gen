import QuickLook
import SwiftUI

/// 生成完成后展示 Excel / 打印预览，并提供打印、分享与存储到文件。
struct ResultView: View {
    let file: GeneratedFile
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .sheet

    private enum Mode: String, CaseIterable, Identifiable {
        case sheet = "表格"
        case print = "打印预览"

        var id: Self { self }
    }

    private var title: String { file.excelURL.deletingPathExtension().lastPathComponent }

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: mode == .sheet ? file.excelURL : file.pdfURL)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Picker("预览", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("完成") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            PrintService.print(pdf: file.pdfURL, jobName: title)
                        } label: {
                            Label("打印", systemImage: "printer")
                        }

                        Menu {
                            ShareLink(item: file.excelURL) {
                                Label("分享 Excel", systemImage: "tablecells")
                            }
                            ShareLink(item: file.pdfURL) {
                                Label("分享 PDF", systemImage: "doc.richtext")
                            }
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                    }
                }
        }
    }
}

private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
