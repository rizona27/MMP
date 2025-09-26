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
        UpdateLog(version: "Version 1.0.0", description: "初代版本。\n基金导入和API调用逻辑构建。"),
        UpdateLog(version: "Version 1.2.0", description: "重构客户、日志页面，新增排行页面，使用更流畅了。"),
        UpdateLog(version: "Version 1.3.0", description: "一览页面逻辑更新，日志逻辑和输出模式、近期收益率完善。"),
        UpdateLog(version: "Version 1.4.0", description: "修改了Logo和名称。\nAPI数据接口冗余，修正跳转功能。"),
        UpdateLog(version: "Version 1.5.0", description: "增加隐私模式。"),
        UpdateLog(version: "Version 1.5.6", description: "API净值读取错误修正，数据导入刷新模式更新。"),
        UpdateLog(version: "Version 1.5.8", description: "收益率字段及导入逻辑完善。"),
        UpdateLog(version: "Version 1.5.9", description: "客户页面刷新模式更新。"),
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
                        Text("易基暴富")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(Color(hex: "FFD700"))
                        Text("Version: 1.5.9      By: rizona.cn@gmail.com")
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

                        Text("跟踪管理多客户基金持仓，提供最新净值查询、收益统计等功能。\n目前数据接口优选同花顺，更新时间略早于其他三端接口。")
                            .font(.body)
                            .foregroundColor(.secondary)

                        Text("主要包括：")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.top, 10)

                        BulletPointView(text: "净值自动化：更新基金净值数据。")
                            .foregroundColor(Color(hex: "3498DB"))
                        BulletPointView(text: "多客户管理：客户分组查看管理持仓。")
                            .foregroundColor(Color(hex: "2ECC71"))
                        BulletPointView(text: "报告一键生成：模板化持仓收益。")
                            .foregroundColor(Color(hex: "E74C3C"))
                        BulletPointView(text: "数据持久化：数据本地保存。")
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
