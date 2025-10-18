import SwiftUI

struct UpdateLog: Identifiable {
    let id = UUID()
    let version: String
    let description: String
}

class UpdateLogViewModel: ObservableObject {
    @Published var currentIndex: Int = 0
    private var timer: Timer?

    let logs: [UpdateLog] = [
        UpdateLog(version: "Version 1.0.0", description: "初代版本，基础导入导出功能和API调用逻辑构建。"),
        UpdateLog(version: "Version 1.2.0", description: "重构客户、日志页，新增排行页，优化程序使用。"),
        UpdateLog(version: "Version 1.3.0", description: "一览页逻辑更新，重构日志分类、完善收益率指标。"),
        UpdateLog(version: "Version 1.4.0", description: "增加Logo和App名称。\n新增冗余API接口。"),
        UpdateLog(version: "Version 1.5.0", description: "增加隐私模式。"),
        UpdateLog(version: "Version 1.5.5", description: "API错误修正，数据导入刷新模式更新。"),
        UpdateLog(version: "Version 1.5.7", description: "收益率字段及导入逻辑完善。"),
        UpdateLog(version: "Version 1.5.9", description: "客户页刷新模式更新。"),
        UpdateLog(version: "Version 1.6.0", description: "客户页右上角更新进度展示，适配隐私模式。"),
        UpdateLog(version: "Version 1.6.1", description: "一览页增加搜索栏，优化数据更新提示。"),
        UpdateLog(version: "Version 1.6.2", description: "统一一览、客户界面、卡片UI。"),
        UpdateLog(version: "Version 1.6.3", description: "去除定位栏、新增编辑模式的隐私开关。"),
        UpdateLog(version: "Version 1.6.4", description: "渐变动画及Toast模块更新。"),
        UpdateLog(version: "Version X.", description: "To be continued...")
    ]

    init() {

        stopScrolling()
        startScrolling()
    }

    func startScrolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            withAnimation(.easeInOut(duration: 1.0)) {
                self.currentIndex = (self.currentIndex + 1) % self.logs.count
            }
        }
    }

    func stopScrolling() {
        timer?.invalidate()
        timer = nil
    }
    
    deinit {
        stopScrolling()
    }
}

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = UpdateLogViewModel()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("一基暴富")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "FFD700"))
                        Text("Version: 1.6.4      By: rizona.cn@gmail.com")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("更新日志：")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(viewModel.logs.indices, id: \.self) { index in
                                        let log = viewModel.logs[index]
                                        BulletPointView(text: "\(log.version)\n\(log.description)")
                                            .foregroundColor(.secondary)
                                            .id(index)
                                    }
                                }
                                .padding()
                            }
                            .frame(height: 100)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .onChange(of: viewModel.currentIndex) { _, newIndex in
                                withAnimation(.easeInOut(duration: 1.0)) {
                                    proxy.scrollTo(newIndex, anchor: .top)
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("功能介绍")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                            .padding(.bottom, 5)

                        Text("跟踪管理多客户基金持仓，提供最新净值查询、收益统计等功能。\n数据接口暂时优选同花顺((更新时间略早于其他接口)。")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("主要包括：")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.top, 10)

                        BulletPointView(text: "数据自动化：自动更新净值数据。")
                            .foregroundColor(Color(hex: "3498DB"))
                        BulletPointView(text: "数据持久化：本地保存客户数据。")
                            .foregroundColor(Color(hex: "2ECC71"))
                        BulletPointView(text: "客户多重管理：分组查看管理持仓。")
                            .foregroundColor(Color(hex: "E74C3C"))
                        BulletPointView(text: "报告一键生成：模板总结持仓收益。")
                            .foregroundColor(Color(hex: "F39C12"))
                    }

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("朕知道了") {
                        dismiss()
                    }
                }
            }
            .onDisappear {
                viewModel.stopScrolling()
            }
        }
    }
}

struct BulletPointView: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(.accentColor)
                .padding(.top, 6)
            Text(text)
        }
    }
}
