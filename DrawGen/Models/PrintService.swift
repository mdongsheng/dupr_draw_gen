import UIKit

/// 调起系统打印面板，打印已渲染好的 PDF（每组一页，A4 横向）。
enum PrintService {
    @MainActor
    static func print(pdf url: URL, jobName: String) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.orientation = .landscape
        info.jobName = jobName

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.showsNumberOfCopies = true
        controller.printingItem = url
        controller.present(animated: true)
    }
}
