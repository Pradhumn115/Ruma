import SwiftUI
import SplitView
import SwiftfulLoadingIndicators
import MarkdownUI






struct ModelHubView: View {
    
    @State var selectedSidebarView: String = "MyModels"
    @StateObject var viewModel = ModelHubViewModel()
    
    var body: some View {
        HStack(spacing: 0){
            // Simplified Sidebar
            VStack(spacing: 12){
                // Header
                VStack(spacing: 4) {
                    Image(systemName: "brain.head.profile")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text("Ruma AI")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 16)
                
                // Navigation buttons
                SidebarButton(
                    icon: "server.rack",
                    title: "Models",
                    isSelected: selectedSidebarView == "MyModels"
                ) {
                    selectedSidebarView = "MyModels"
                }
                
                SidebarButton(
                    icon: "magnifyingglass",
                    title: "Discover",
                    isSelected: selectedSidebarView == "SearchModel"
                ) {
                    selectedSidebarView = "SearchModel"
                }
                
                SidebarButton(
                    icon: "key.fill",
                    title: "API Keys",
                    isSelected: selectedSidebarView == "APIKey"
                ) {
                    selectedSidebarView = "APIKey"
                }
                
                SidebarButton(
                    icon: "arrow.down.circle",
                    title: "Updates",
                    isSelected: selectedSidebarView == "Updates"
                ) {
                    selectedSidebarView = "Updates"
                }
                
                SidebarButton(
                    icon: "trash.circle",
                    title: "Cleanup",
                    isSelected: selectedSidebarView == "Cleanup"
                ) {
                    selectedSidebarView = "Cleanup"
                }
                
                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .frame(width: 120)
            .background(Material.ultraThin)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .frame(width: 1)
                    .foregroundColor(.gray.opacity(0.3))
            }
            
            // Content Area
            Group {
                if selectedSidebarView == "SearchModel" {
                    SearchModels()
                        .environmentObject(viewModel)
                } else if selectedSidebarView == "MyModels" {
                    ImprovedMyModels()
                        .environmentObject(viewModel)
                } else if selectedSidebarView == "APIKey" {
                    APIKey()
                } else if selectedSidebarView == "Updates" {
                    SimpleUpdatesView()
                } else if selectedSidebarView == "Cleanup" {
                    CleanupView(appState: AppState())
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Material.ultraThin)
        .frame(minWidth: 900, minHeight: 500)
    }
    
    
}

struct ImprovedMyModels: View {
    @EnvironmentObject var viewModel: ModelHubViewModel
    @State private var showingDirectorySettings = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model Management")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Manage your local and API models")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Settings and Refresh buttons
                    HStack(spacing: 12) {
                        // Models directory settings button
                        Button {
                            showingDirectorySettings = true
                        } label: {
                            Image(systemName: "gear")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .help("Models Directory Settings")
                        
                        // Refresh button
                        Button {
                            Task {
                                await viewModel.getCurrentModelStatus()
                                await viewModel.fetchDownloadedModels()
                                await viewModel.fetchAPIModels()
                                await viewModel.fetchVisionModels()
                                await viewModel.fetchVisionModelStatus()
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                        .help("Refresh Models")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                
                // Current Model Status
                if let currentModelID = viewModel.currentSelectedModelID {
                    CurrentModelBanner(modelID: currentModelID)
                        .padding(.horizontal, 24)
                }
                
                // Downloads Section
                if !viewModel.downloadingModels.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Active Downloads")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                        
                        ForEach(viewModel.downloadingModels) { model in
                            SimpleDownloadCard(model: model)
                                .environmentObject(viewModel)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                
                // Available Local Models Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Local Models")
                        .font(.headline)
                        .fontWeight(.bold)
                        .padding(.horizontal, 24)
                    
                    ForEach(viewModel.downloadedModels) { model in
                        SimpleModelCard(model: model)
                            .environmentObject(viewModel)
                            .padding(.horizontal, 24)
                    }
                }
                
                // Vision Models Section
                if !viewModel.visionModels.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Vision Models")
                                .font(.headline)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            if viewModel.isVisionModelLoaded {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("Vision Active")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        ForEach(viewModel.visionModels) { model in
                            VisionModelCard(model: model)
                                .environmentObject(viewModel)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                
                // API Models Section
                if !viewModel.apiModels.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("API Models")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 24)
                        
                        ForEach(viewModel.apiModels) { model in
                            APIModelCard(model: model)
                                .environmentObject(viewModel)
                                .padding(.horizontal, 24)
                        }
                    }
                }
                
                Spacer(minLength: 20)
            }
        }
        .onAppear {
            Task {
                await viewModel.getCurrentModelStatus()
                await viewModel.fetchDownloadedModels()
                await viewModel.fetchAPIModels()
                await viewModel.fetchVisionModels()
                await viewModel.fetchVisionModelStatus()
            }
        }
        .sheet(isPresented: $showingDirectorySettings) {
            ModelDirectorySettings()
                .environmentObject(viewModel)
        }
    }
}

struct SingleMyModelInfo: View {
    @State var progress: Double = 0.2
    var body: some View {
        HStack{
//            Text("Model Name")
//                .font(.title3)
//            VStack(spacing:0){
//                Text("Downloading...")
//                    .font(.caption)
//                ProgressView(value: progress)
//                    .padding(.bottom,10)
//                    
//            }
//            Text(String(format: "%.1f%%", progress * 100))
            
            Button{
                
            }label: {
                Text("Pause")
            }
            
            Button{
                
            }label: {
                Text("Resume")
            }
            
            Button{
                
            }label: {
                Text("Delete")
            }
        }
    }
}

struct APIKey: View {
    @StateObject private var apiKeyManager = APIKeyManager()
    @State private var selectedProvider: String = ""
    @State private var selectedModel: String = ""
    @State private var newAPIKey: String = ""
    @State private var customName: String = ""
    @State private var showAddKeyForm: Bool = false
    @State private var isAddingKey: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("API Keys")
                    .font(.system(size: 24))
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    Task {
                        await apiKeyManager.reload()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                Button {
                    showAddKeyForm.toggle()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(.bottom, 10)
            
            // Add new API key form
            if showAddKeyForm {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Add New API Key")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    // Provider selection
                    HStack {
                        Text("Provider:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if apiKeyManager.supportedProviders.isEmpty {
                            Text("No providers loaded")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            Picker("Provider", selection: $selectedProvider) {
                                Text("Select Provider").tag("")
                                ForEach(apiKeyManager.supportedProviders) { provider in
                                    Text(provider.name).tag(provider.id)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        
                        Text("(\(apiKeyManager.supportedProviders.count) available)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Model selection
//                    if !selectedProvider.isEmpty {
//                        HStack {
//                            Text("Model:")
//                                .font(.subheadline)
//                                .foregroundColor(.secondary)
//                            
//                            let availableModels = apiKeyManager.getModels(for: selectedProvider)
//                            if availableModels.isEmpty {
//                                Text("No models available")
//                                    .foregroundColor(.secondary)
//                                    .font(.caption)
//                            } else {
//                                Picker("Model", selection: $selectedModel) {
//                                    Text("Select Model (Optional)").tag("")
//                                    ForEach(availableModels, id: \.self) { model in
//                                        Text(model).tag(model)
//                                    }
//                                }
//                                .pickerStyle(.menu)
//                            }
//                            
//                            Text("(\(availableModels.count) available)")
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                        }
//                        .onChange(of: selectedProvider) { _,_ in
//                            selectedModel = "" // Reset model when provider changes
//                        }
//                    }
                    
                    // Custom name (optional)
                    VStack(alignment: .leading) {
                        Text("Name (Optional):")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        TextField("Custom name for this key", text: $customName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // API Key input
                    VStack(alignment: .leading) {
                        Text("API Key:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter your API key", text: $newAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Action buttons
                    HStack {
                        Button("Cancel") {
                            showAddKeyForm = false
                            resetForm()
                        }
                        .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Add Key") {
                            Task {
                                await addAPIKey()
                            }
                        }
                        .disabled(selectedProvider.isEmpty || newAPIKey.isEmpty || isAddingKey)
                        .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(.black.opacity(0.2))
                .cornerRadius(10)
            }
            
            // Existing API Keys
            if apiKeyManager.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading API keys...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else if apiKeyManager.apiKeys.isEmpty {
                VStack {
                    Image(systemName: "key.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No API keys configured")
                        .foregroundColor(.secondary)
                    Text("Add your first API key to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(apiKeyManager.apiKeys) { keyInfo in
                            APIKeyRow(keyInfo: keyInfo, apiKeyManager: apiKeyManager)
                        }
                    }
                }
            }
            
            // Error message
            if !apiKeyManager.errorMessage.isEmpty {
                Text(apiKeyManager.errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.top)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            Task {
                await apiKeyManager.loadSupportedProviders()
                await apiKeyManager.loadAPIKeys()
            }
        }
    }
    
    private func addAPIKey() async {
        isAddingKey = true
        let success = await apiKeyManager.addAPIKey(
            provider: selectedProvider,
            apiKey: newAPIKey,
            name: customName.isEmpty ? nil : customName,
            model: selectedModel.isEmpty ? nil : selectedModel
        )
        
        if success {
            showAddKeyForm = false
            resetForm()
        }
        isAddingKey = false
    }
    
    private func resetForm() {
        selectedProvider = ""
        selectedModel = ""
        newAPIKey = ""
        customName = ""
    }
}

struct APIKeyRow: View {
    let keyInfo: APIKeyInfo
    let apiKeyManager: APIKeyManager
    @State private var isTesting: Bool = false
    @State private var showDeleteAlert: Bool = false
    
    var body: some View {
        HStack {
            // Provider icon and info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    // Provider image or icon
                    if keyInfo.provider == "llm_vin" {
                        Image("llm.vin")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: getProviderIcon(keyInfo.provider))
                            .font(.title2)
                            .foregroundColor(getProviderColor(keyInfo.provider))
                    }
                    
                    Text(keyInfo.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(keyInfo.masked_key)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospaced()
                
                if let model = keyInfo.model, !model.isEmpty {
                    Text("Model: \(model)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                HStack {
                    Image(systemName: apiKeyManager.getStatusIcon(for: keyInfo.status))
                        .foregroundColor(apiKeyManager.getStatusColor(for: keyInfo.status))
                    Text(keyInfo.status.capitalized)
                        .font(.caption)
                        .foregroundColor(apiKeyManager.getStatusColor(for: keyInfo.status))
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 8) {
                Button {
                    Task {
                        isTesting = true
                        await apiKeyManager.testAPIKey(provider: keyInfo.provider)
                        isTesting = false
                    }
                } label: {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark.circle")
                    }
                }
                .disabled(isTesting)
                .foregroundColor(.blue)
                
                Button {
                    showDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(.black.opacity(0.2))
        .cornerRadius(8)
        .alert("Delete API Key", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await apiKeyManager.removeAPIKey(provider: keyInfo.provider)
                }
            }
        } message: {
            Text("Are you sure you want to delete the API key for \(keyInfo.name)?")
        }
    }
    
    private func getProviderIcon(_ provider: String) -> String {
        switch provider {
        case "openai":
            return "brain.head.profile"
        case "claude":
            return "doc.text"
        default:
            return "key"
        }
    }
    
    private func getProviderColor(_ provider: String) -> Color {
        switch provider {
        case "openai":
            return .green
        case "claude":
            return .purple
        case "llm_vin":
            return .blue
        default:
            return .gray
        }
    }
}

struct MyModelsView: View {
    @EnvironmentObject private var vm : ModelHubViewModel
    
    var body: some View {
        VStack(spacing:0) {
            
            Text("Downloading Models")
                .padding(10)
            
            List(vm.downloadingModels) { model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.id).font(.headline).lineLimit(1)
                        Spacer()
                        Text(model.status).font(.subheadline).foregroundColor(.secondary)
                    }
                    let progress = vm.downloadProgress[model.id] ?? (Double(model.percentage) / 100.0)
                    
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    
                    Text(String(format: "%.2f %%", progress*100))
                        .font(.caption).foregroundColor(.secondary)
                    
                    // Add control buttons for each download
                    HStack {
                        Button("Pause") {
                            vm.pauseDownload(uniqueId: model.id)
                        }
                        .disabled(model.status != "downloading")
                        
                        Button("Resume") {
                            vm.resumeDownload(uniqueId: model.id)
                        }
                        .disabled(model.status != "paused")
                        
                        Button("Cancel") {
                            vm.cancelDownload(uniqueId: model.id)
                        }
                        .disabled(model.status == "ready")
                        
                        Button("Delete") {
                            vm.deleteModel(uniqueId: model.id)
                        }
                        .foregroundColor(.red)
                    }
                    .font(.caption)
                }
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .background(.black.opacity(0.2))
            .frame(maxHeight: .infinity)
            .cornerRadius(8)
            
            
            Text("My Models")
                .padding(10)
            
            List(vm.downloadedModels) { model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.id).font(.headline).lineLimit(1)
                        Spacer()
                        
                        Button{
                            Task {
                                await vm.switchToModel(modelId: model.id)
                            }
                        }label:{
                            if vm.isSwitchingModel && vm.currentSelectedModelID == model.id {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Switching...")
                                        .font(.caption)
                                }
                            } else if vm.currentSelectedModelID == model.id {
                                Text("Current Model")
                                    .foregroundStyle(.green)
                                    .fontWeight(.medium)
                            } else {
                                Text("Use Model")
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .background(.white.opacity(0.1))
                        .cornerRadius(5)
                        
                        
                            
                        Text(model.status).font(.subheadline).foregroundColor(.secondary)
                    }
                    ProgressView(value: model.percentage / 100)
                        .progressViewStyle(.linear)
                    Text(String(format: "%.2f %%", model.percentage))
                        .font(.caption).foregroundColor(.secondary)
                    
                    // Add delete button for completed downloads
                    HStack {
                        Spacer()
                        Button{
                            vm.deleteModel(uniqueId: model.id)
                        }label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                        
                        .padding(6)
                        .background{
                            Circle()
                                .fill(Color.red.opacity(0.2))
                                
                        }
                        
                        
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
            .scrollContentBackground(.hidden)
            .background(.black.opacity(0.2))
            .cornerRadius(8)
            
            
            
        }
        .navigationTitle("Downloads")
        .onAppear{
            Task {
                await vm.getCurrentModelStatus()
                await vm.fetchDownloadedModels()
            }
        }

    }
}




// MARK: - Supporting Views

struct SidebarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? .blue : .secondary)
                
                Text(title)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? .blue.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct CurrentModelBanner: View {
    let modelID: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Currently Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(modelID)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Ready")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(16)
        .background(.green.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SimpleDownloadCard: View {
    let model: DownloadInfo
    @EnvironmentObject private var viewModel: ModelHubViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(model.id)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text(model.status.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.2))
                    .foregroundStyle(.blue)
                    .cornerRadius(6)
            }
            
            let progress = viewModel.downloadProgress[model.id] ?? (Double(model.percentage) / 100.0)
            
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            
            HStack {
                Text(String(format: "%.1f%%", progress * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 8) {
                    if model.status == "downloading" {
                        Button("Pause") {
                            viewModel.pauseDownload(uniqueId: model.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    
                    if model.status == "paused" {
                        Button("Resume") {
                            viewModel.resumeDownload(uniqueId: model.id)
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    
                    Button("Delete") {
                        viewModel.deleteModel(uniqueId: model.id)
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                }
            }
        }
        .padding(16)
        .background(.thickMaterial)
        .cornerRadius(12)
    }
}

struct SimpleModelCard: View {
    let model: DownloadInfo
    @EnvironmentObject private var viewModel: ModelHubViewModel
    
    var body: some View {
        HStack(spacing: 16) {
            // Model info
            VStack(alignment: .leading, spacing: 8) {
                Text(model.id)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                HStack {
                    Label("Local Model", systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if model.status == "ready" {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                if viewModel.currentSelectedModelID == model.id {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Button("Use Model") {
                        Task {
                            await viewModel.switchToModel(modelId: model.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSwitchingModel)
                }
                
                Menu {
                    Button("Delete", role: .destructive) {
                        viewModel.deleteModel(uniqueId: model.id)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(.thickMaterial)
        .cornerRadius(12)
    }
}

struct APIModelCard: View {
    let model: APIModelInfo
    @EnvironmentObject private var viewModel: ModelHubViewModel
    
    var providerIcon: String {
        switch model.provider {
        case "openai": return "brain.head.profile"
        case "claude": return "doc.text"
        case "llm_vin": return "cloud"
        default: return "globe"
        }
    }
    
    var providerColor: Color {
        switch model.provider {
        case "openai": return .green
        case "claude": return .purple
        case "llm_vin": return .blue
        default: return .gray
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Model info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.modelId.components(separatedBy: ":").last ?? model.modelId)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    // Image model badge
                    if model.isImageModel {
                        Label("Image", systemImage: "photo")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }
                
                HStack {
                    Label(model.provider.capitalized, systemImage: providerIcon)
                        .font(.caption)
                        .foregroundStyle(providerColor)
                    
                    if model.available {
                        Label("Available", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                
                // Capabilities badges
                if !model.capabilities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(model.capabilities, id: \.self) { capability in
                            Text(capability.replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                if viewModel.currentSelectedModelID == model.modelId {
                    Label("Current", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.green.opacity(0.2))
                        .cornerRadius(8)
                } else {
                    Button(model.isImageModel ? "Use for Images" : "Use Model") {
                        Task {
                            await viewModel.switchToModel(modelId: model.modelId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.isSwitchingModel || !model.available)
                }
            }
        }
        .padding(16)
        .background(.thickMaterial)
        .cornerRadius(12)
        .overlay(
            // Special border for image models
            RoundedRectangle(cornerRadius: 12)
                .stroke(model.isImageModel ? .orange.opacity(0.3) : .clear, lineWidth: 1)
        )
    }
}

struct UpdatesView: View {
    @StateObject private var appState = AppState()
    @State private var showInstallConfirmation = false
    let progressTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App Updates")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Keep Ruma up to date")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        await appState.checkForUpdatesAction()
                    }
                }) {
                    HStack {
                        if appState.isCheckingForUpdates {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Check for Updates")
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(appState.isCheckingForUpdates)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Current Version Info
            ScrollView{
                VStack(alignment: .leading, spacing: 16) {
                    Text("Current Version")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ruma")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("Version \(appState.currentAppVersion)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.green)
                                    .frame(width: 8, height: 8)
                                Text("Installed")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        
                        if let updateInfo = appState.updateInfo {
                            Divider()
                            
                            if updateInfo.update_available {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.orange)
                                        Text("Update Available")
                                            .font(.headline)
                                            .foregroundColor(.orange)
                                    }
                                    
                                    if let latestVersion = updateInfo.latest_version {
                                        Text("Version \(latestVersion) is now available")
                                            .font(.subheadline)
                                    }
                                    
                                    if let downloadSize = updateInfo.download_size {
                                        Text("Download size: \(appState.formatBytes(downloadSize))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    if let releaseNotes = updateInfo.release_notes, !releaseNotes.isEmpty {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text("What's New:")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            Text(releaseNotes)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, 8)
                                        }
                                    }
                                    
                                    // Simplified Update Actions
                                    VStack(alignment: .leading, spacing: 16) {
                                        // Auto-Update Setting
                                        HStack {
                                            Toggle("Automatically install updates", isOn: $appState.autoUpdateEnabled)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            
                                            Spacer()
                                            
                                            Image(systemName: appState.autoUpdateEnabled ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(appState.autoUpdateEnabled ? .green : .secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(.secondary.opacity(0.1))
                                        .cornerRadius(8)
                                        
                                        // Download Progress (if downloading)
                                        if appState.isDownloadingUpdate || appState.downloadProgress > 0 {
                                            VStack(alignment: .leading, spacing: 8) {
                                                HStack {
                                                    Text(appState.isPaused ? "Download Paused" : (appState.isInstallingUpdate ? "Installing..." : "Downloading..."))
                                                        .font(.subheadline)
                                                        .fontWeight(.medium)
                                                    
                                                    Spacer()
                                                    
                                                    if appState.downloadTotalBytes > 0 {
                                                        Text("\(appState.formatBytes(appState.downloadBytesReceived)) / \(appState.formatBytes(appState.downloadTotalBytes))")
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                }
                                                
                                                ProgressView(value: appState.downloadProgress)
                                                    .progressViewStyle(.linear)
                                                    .tint(appState.autoUpdateEnabled ? .purple : .blue)
                                                    .onReceive(progressTimer) { _ in
                                                                Task { await appState.loadDownloadProgress() }
                                                              }
                                                
                                                Text("\(Int(appState.downloadProgress * 100))% complete")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                // Download Control Buttons
                                                if appState.isDownloadingUpdate || appState.canResumeDownload {
                                                    HStack(spacing: 8) {
                                                        if appState.isPaused || appState.canResumeDownload {
                                                            Button("Resume") {
                                                                Task { await appState.resumeUpdateDownload() }
                                                            }
                                                            .buttonStyle(.bordered)
                                                            .controlSize(.small)
                                                        } else {
                                                            Button("Pause") {
                                                                Task { await appState.pauseUpdateDownload() }
                                                            }
                                                            .buttonStyle(.bordered)
                                                            .controlSize(.small)
                                                        }
                                                        
                                                        Button("Cancel") {
                                                            Task { await appState.cancelUpdateDownload() }
                                                        }
                                                        .buttonStyle(.bordered)
                                                        .controlSize(.small)
                                                        .tint(.red)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(.blue.opacity(0.1))
                                            .cornerRadius(8)
                                        }
                                        
                                        // Main Download/Install Button
                                        if !appState.isDownloadingUpdate && !appState.isInstallingUpdate {
                                            if appState.downloadedUpdatePath == nil {
                                                // Download Button
                                                Button(action: {
                                                    Task {
                                                        await appState.unifiedUpdateAction()
                                                    }
                                                }) {
                                                    HStack {
                                                        Image(systemName: appState.autoUpdateEnabled ? "arrow.down.app.fill" : "arrow.down.circle.fill")
                                                        Text(appState.autoUpdateEnabled ? "Download & Install Update" : "Download Update")
                                                    }
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(appState.autoUpdateEnabled ? .purple : .blue)
                                                    .cornerRadius(10)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            } else {
                                                // Install Button (for manual downloads)
                                                Button(action: {
                                                    showInstallConfirmation = true
                                                }) {
                                                    HStack {
                                                        Image(systemName: "square.and.arrow.down.fill")
                                                        Text("Install Update")
                                                    }
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.vertical, 12)
                                                    .background(.green)
                                                    .cornerRadius(10)
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                        }
                                        
                                        if appState.autoUpdateEnabled {
                                            Text("Updates will be downloaded and installed automatically with industry-level security checks")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        } else {
                                            Text("Updates will be downloaded only. You can install them manually when ready")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }
                                }
                                .padding()
                                .background(.orange.opacity(0.1))
                                .cornerRadius(12)
                            } else {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("You're running the latest version")
                                        .font(.subheadline)
                                        .foregroundColor(.green)
                                }
                                .padding()
                                .background(.green.opacity(0.1))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding(20)
                    .background(.thickMaterial)
                    .cornerRadius(16)
                    .padding(.horizontal, 24)
                }
            }
            
            // Status Message
            if !appState.updateMessage.isEmpty {
                Text(appState.updateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
        }
        .onAppear {
            Task {
                await appState.loadAppVersion()
                await appState.loadDownloadProgress()
                
                // If we have update info, check if download is already complete
                if let updateInfo = appState.updateInfo,
                   updateInfo.update_available,
                   let downloadUrl = updateInfo.download_url {
                    await appState.checkCompletedDownload(downloadUrl: downloadUrl)
                }
            }
        }
        .alert("Install Update", isPresented: $showInstallConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Install", role: .destructive) {
                Task {
                    await appState.installUpdateAction()
                }
            }
        } message: {
            Text("Installing this update will restart the application. Make sure all your work is saved before proceeding.")
        }
        .onDisappear {
          progressTimer.upstream.connect().cancel()  // stop the timer when view goes away
        }
    }
}


struct VisionModelCard: View {
    let model: VisionModelInfo
    @EnvironmentObject var viewModel: ModelHubViewModel
    @State private var isLoading = false
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Model info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    
                    // Vision model badge
                    Label("Vision", systemImage: "eye.fill")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .cornerRadius(4)
                    
                    if model.recommended {
                        Label("Recommended", systemImage: "star.fill")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.yellow.opacity(0.2))
                            .foregroundStyle(.orange)
                            .cornerRadius(4)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack {
                    Label(model.size, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    if model.isLocal {
                        Label("Local", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Download Available", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    
                    if model.isLoaded {
                        Label("Loaded", systemImage: "bolt.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            VStack(spacing: 8) {
                if model.isLoaded {
                    Button("Unload") {
                        isLoading = true
                        Task {
                            await viewModel.unloadVisionModel()
                            isLoading = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoading)
                } else if model.isLocal {
                    Button("Load") {
                        isLoading = true
                        Task {
                            await viewModel.loadVisionModel(modelKey: model.modelId)
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                } else {
                    Button("Download") {
                        isLoading = true
                        Task {
                            // Use the fullModelName for proper download with download manager
                            let modelIdToDownload = model.fullModelName ?? model.name
                            await viewModel.startDownload(modelId: modelIdToDownload, modelType: "mlx", files: [])
                            isLoading = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading)
                }
                
                // Delete button for local vision models
                if model.isLocal {
                    Button("Delete") {
                        showingDeleteConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .disabled(isLoading)
                }
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(16)
        .background(.thickMaterial)
        .cornerRadius(12)
        .alert("Delete Vision Model", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                isLoading = true
                Task {
                    // Use the full model name for proper unique ID generation
                    let uniqueId = viewModel.generateUniqueId(
                        modelId: model.fullModelName ?? model.modelId,
                        modelType: "mlx",
                        files: []
                    )
                    viewModel.deleteModel(uniqueId: uniqueId)
                    isLoading = false
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(model.name)'? This action cannot be undone.")
        }
    }
}

#Preview {
    ModelHubView()
}
