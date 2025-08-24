import SwiftUI

// MARK: - AddFavoriteView UI
struct AddFavoriteView: View {
    @EnvironmentObject var dataManager: DataManager
    @EnvironmentObject var fundService: FundService
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State Variables
    @State private var name: String = ""
    @State private var url: String = "https://"
    
    // MARK: - Real-time Validation State
    @State private var isNameValid: Bool = true
    @State private var isUrlValid: Bool = true
    @State private var showingAlert: Bool = false
    
    // MARK: - Computed Properties
    private var isFormValid: Bool {
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               URL(string: url) != nil
    }

    // MARK: - View Body
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Group {
                        // 名称输入卡片
                        inputCard(title: "名称", required: true, error: .constant(nil)) {
                            TextField("例如：Apple 官网", text: $name)
                                .onChange(of: name) { _, newValue in
                                    isNameValid = !newValue.isEmpty
                                }
                        }
                        
                        // 网址输入卡片
                        inputCard(title: "网址", required: true, error: .constant(nil)) {
                            TextField("例如：https://www.apple.com", text: $url)
                                .keyboardType(.URL)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onChange(of: url) { _, newValue in
                                    isUrlValid = URL(string: newValue) != nil
                                }
                        }
                    }
                    .padding(.horizontal)
                    .scaleEffect(0.95)
                    
                    Spacer()
                    
                    Button("添加并保存") {
                        saveFavorite()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
                .navigationTitle("新增收藏")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                }
            }
        }
        .alert("信息有误", isPresented: $showingAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请确保名称和网址都已填写且格式正确。")
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
    
    // MARK: - Helper Views
    private func inputCard<Content: View>(title: String, required: Bool, error: Binding<String?>, @ViewBuilder content: () -> Content) -> some View {
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
                content()
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(15)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            if let errorMessage = error.wrappedValue {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.leading)
            }
        }
    }

    // MARK: - Save Method
    private func saveFavorite() {
        if isFormValid {
            let newFavorite = FavoriteItem(name: name, url: url)
            dataManager.favorites.append(newFavorite)
            dataManager.saveData()
            fundService.addLog("新增收藏: 地址'\(name)'已添加。", type: .success)
            dismiss()
        } else {
            showingAlert = true
        }
    }
}
