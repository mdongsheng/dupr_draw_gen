# DUPR对阵表

一个简洁的 iOS 应用：粘贴分组名单，一键把队伍填入 Excel 对阵表模板（`A1–A6`、`B1–B6`），并可预览、分享或存到「文件」。

## 使用

1. 粘贴名单（或点「示例」）：

   ```
   A组
   鹅蛋/Andy
   椰子/铁人
   ...

   B组
   曹总/黄金杰
   ...
   ```

   分组标题支持 `A组`、`A 组：`、`Group A`；行首编号 `1.`、`1、` 会自动去掉。
2. 下方实时预览每个位置（A1…A6 / B1…B6）对应的队伍，数量不对或重复会提示。
3. 点「生成 Excel」，预览页可在「表格 / 打印预览」间切换；右上角可**打印**（A 组一页、B 组一页，A4 横向），或分享 Excel / PDF。生成的文件也保存在「文件 › 我的 iPhone › 对阵表」。

## 打印

- 应用内打印：按模板样式（配色、边框、斜线、合并单元格）把 `A1:K9`、`A10:K18` 各渲染为一页 A4 横向 PDF，再调起系统打印面板。
- 生成的 xlsx 也写好了打印设置（A4 横向、宽度缩放到一页、两个打印区域各占一页），在 Excel / Numbers 中直接打印效果相同。
- 打印区域定义在 `TemplateLayout.standard.printRanges`。

## 模板

内置模板为 `DrawGen/Resources/template.xlsx`，写入位置：

| 分组 | 横向表头 | 纵向表头 |
| --- | --- | --- |
| A 组 | `C3:H3` | `B4:B9` |
| B 组 | `C12:H12` | `B13:B18` |

只改这些单元格的内容，样式、配色、合并单元格等全部保留。也可在应用中「导入模板…」，使用相同布局的其他 xlsx。布局定义在 `DrawGen/Excel/XLSXTemplateFiller.swift` 的 `TemplateLayout.standard`。

## 构建

- Xcode 16 或更高，iOS 17+，无第三方依赖。
- 打开 `DrawGen.xcodeproj`，在 Signing & Capabilities 中选择你的 Team 后运行。

## 品牌

- App 图标与首页 Logo 来自「大美友约 Pickleball Club」标志（`DrawGen/Assets.xcassets/AppIcon`、`BrandLogo`），源文件见 `Design/logo.ai`。

## 结构

```
DrawGen/
  DrawGenApp.swift
  Models/   DrawParser（解析名单与校验）、TemplateStore（模板与导出路径）、PrintService（系统打印）
  Excel/    ZipArchive（xlsx 读写，基于系统 Compression）、XLSXTemplateFiller（写入单元格）、
            PrintSetup（xlsx 打印设置）、XLSXWorkbook + XLSXPrintRenderer（读取样式并渲染打印 PDF）
  Views/    ContentView、GroupCard、ResultView（QuickLook 预览 + 分享）、Theme
```
