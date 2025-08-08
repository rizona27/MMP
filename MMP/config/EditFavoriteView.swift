import SwiftUI

struct EditFavoriteView: View {
    @EnvironmentObject var dataManager: DataManager
    @Environment(\.dismiss) var dismiss
    @State var favorite: FavoriteItem
    
    @State private var name: String
    @State private var url: String
    @State private var isNameValid: Bool = true
    @State private var isUrlValid: Bool = true
    @State private var showingAlert: Bool = false

    init(favorite: FavoriteItem) {
        _favorite = State(initialValue: favorite)
        _name = State(initialValue: favorite.name)
        _url = State(initialValue: favorite.url)
    }

    private var isFormValid: Bool {
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               URL(string: url) != nil
    }

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
                                .onChange(of: url) { _, newValue in
                                    isUrlValid = !newValue.isEmpty && URL(string: newValue) != nil
                                }
                        }
                    }
                    .padding(.horizontal)
                    
                    // MARK: - Action Buttons
                    HStack(spacing: 20) {
                        Button("取消") {
                            dismiss()
                        }
                        .buttonStyle(CardButtonStyle(backgroundColor: Color.gray.opacity(0.1)))
                        
                        Button("保存") {
                            saveFavorite()
                        }
                        .buttonStyle(CardButtonStyle(backgroundColor: isFormValid ? .blue : .gray.opacity(0.1), foregroundColor: isFormValid ? .white : .secondary))
                        .disabled(!isFormValid)
                    }
                    .padding()
                }
                .padding(.top)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.title3)
                            .foregroundColor(.accentColor)
                    }
                }
            }
        }
        .alert("输入有误", isPresented: $showingAlert) {
            Button("确定", role: .cancel) {}
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
            if let index = dataManager.favorites.firstIndex(where: { $0.id == favorite.id }) {
                dataManager.favorites[index].name = name
                dataManager.favorites[index].url = url
                dataManager.saveData()
            }
            dismiss()
        } else {
            showingAlert = true
        }
    }
}
