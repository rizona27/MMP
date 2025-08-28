import SwiftUI

// MARK: - MatchedButtonStyle
struct MatchedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.2 : 0.1))
            .foregroundColor(.accentColor)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}

// MARK: - AddFavoriteView UI
struct AddFavoriteView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State Variables
    @State private var name: String = ""
    @State private var url: String = "https://"
    
    // MARK: - Real-time Validation State & Error Messages
    @State private var nameError: String?
    @State private var urlError: String?

    // MARK: - Computed Properties for Validation
    private var isNameValid: Bool {
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var isUrlValid: Bool {
        // 确保网址包含一个点 '.' 并且是有效的 URL
        return url.contains(".") && URL(string: url) != nil
    }
    
    private var isFormValid: Bool {
        return isNameValid && isUrlValid
    }

    // MARK: - View Body
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                ScrollView {
                    VStack(spacing: 20) {
                        // 名称输入卡片
                        inputCard(title: "名称", required: true, errorMessage: nameError) {
                            TextField("例如：Apple 官网", text: $name)
                                .onChange(of: name) { _, _ in
                                    // 实时验证，如果有效则清空错误信息
                                    if isNameValid {
                                        nameError = nil
                                    }
                                }
                        }
                        
                        // 网址输入卡片
                        inputCard(title: "网址", required: true, errorMessage: urlError) {
                            TextField("例如：https://www.apple.com", text: $url)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: url) { _, _ in
                                    // 实时验证，如果有效则清空错误信息
                                    if isUrlValid {
                                        urlError = nil
                                    }
                                }
                        }
                    }
                    .padding()
                }
                
                // "添加并保存" 按钮
                Button("添加并保存") {
                    saveFavorite()
                }
                .buttonStyle(MatchedButtonStyle())
                .padding(.bottom, 20)
                .disabled(!isFormValid)
                .opacity(isFormValid ? 1.0 : 0.6)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views
    private func inputCard<Content: View>(title: String, required: Bool, errorMessage: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                if required {
                    Text("*")
                        .foregroundColor(.red)
                }
                Spacer()
            }
            content()
            
            if let message = errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(15)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    // MARK: - Save Method
    private func saveFavorite() {
        // 在保存前进行最终验证，以防用户在输入无效后直接点击按钮
        nameError = isNameValid ? nil : "名称不能为空。"
        urlError = isUrlValid ? nil : "请确保网址包含点号，例如：google.com"
        
        if isFormValid {
            let newFavorite = FavoriteItem(name: name, url: url)
            dataManager.favorites.append(newFavorite)
            dataManager.saveData()
            fundService.addLog("新增收藏: 地址'\(name)'已添加。", type: .success)
            dismiss()
        }
    }
}
