import SwiftUI

struct APILogView: View {
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                if fundService.logMessages.isEmpty {
                    Text("暂无API查询日志。")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    List {
                        // 使用 ReversedCollection 来倒序显示日志，最新的在最上面
                        ForEach(fundService.logMessages.reversed(), id: \.self) { log in
                            Text(log)
                                .font(.caption)
                                .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("") // 移除标题
            .navigationBarTitleDisplayMode(.inline) // 确保标题不占用太多空间
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward") // 返回图标
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        fundService.logMessages.removeAll()
                    } label: {
                        Image(systemName: "trash") // 垃圾桶图标
                    }
                }
            }
        }
    }
}
