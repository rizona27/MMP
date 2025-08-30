import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("易基暴富")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("Version: 1.4.3     By: rizona.cn@gmail.com")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // MARK: - 更新日志 (调整高度以显示约两条)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("更新日志：")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                BulletPointView(text: "Version 1.4.0\n修改了Logo和名称。\nAPI数据接口冗余，修正跳转功能。")
                                    .foregroundColor(.secondary)
                                BulletPointView(text: "Version 1.3.0\n一览页面逻辑更新，日志逻辑和输出模式、近期收益率完善。")
                                    .foregroundColor(.secondary)
                                BulletPointView(text: "Version 1.2.0\n重构客户、日志页面，新增排行页面，使用更流畅了。")
                                    .foregroundColor(.secondary)
                                BulletPointView(text: "Version 1.0.0\n初代版本。\n基金导入和API调用逻辑构建。")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        }
                        .frame(height: 100)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("功能介绍")
                            .font(.headline)
                            .padding(.bottom, 5)

                        Text("跟踪管理多客户基金持仓，提供最新基金净值查询、收益统计等功能。")
                            .font(.body)

                        Text("主要包括：")
                            .font(.body)
                            .fontWeight(.medium)
                            .padding(.top, 10)
                            
                        BulletPointView(text: "净值自动化：\n更新基金净值数据。")
                        BulletPointView(text: "多客户管理：\n客户分组查看管理持仓。")
                        BulletPointView(text: "报告一键生成：\n模板化持仓收益。")
                        BulletPointView(text: "数据持久化：\n数据本地保存。")
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
