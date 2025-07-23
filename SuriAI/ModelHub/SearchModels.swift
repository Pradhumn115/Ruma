import SwiftUI
import SplitView
import SwiftfulLoadingIndicators
import MarkdownUI
import Foundation

struct SearchModels: View {
    @EnvironmentObject var viewModel: ModelHubViewModel
    @State var searchModel: String = ""
    @State private var selectedModelID: String? = nil
    @State private var isExpanded = false
    @State private var selectedDownloadKey: String? = nil
    @State private var showSearchHistory = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Filtered model types - LLM, vision-language, and image generation models
    private let allowedModelTags = [
        "text-generation", "text2text-generation", "conversational",
        "question-answering", "summarization", "translation",
        "text-to-image", "image-to-text", "image-classification",
        "feature-extraction", "sentence-similarity", "visual-question-answering",
        "image-text-to-text", "image-segmentation", "object-detection",
        "zero-shot-image-classification", "image-feature-extraction"
    ]
    
    // Vision model indicators
    private let visionModelTags = [
        "image-to-text", "image-classification", "visual-question-answering",
        "image-text-to-text", "image-segmentation", "object-detection",
        "zero-shot-image-classification", "image-feature-extraction"
    ]
    
    // Blocked repositories that have access issues or incorrect metadata
    private let blockedRepos = [
        "meta-llama/", "facebook/", "openai/", "anthropic/",
        "microsoft/DialoGPT", "google/", "deepmind/"
    ]
    
    var selectedModel: ModelInfo? {
        viewModel.searchResults.first { $0.id == selectedModelID }
    }
    
    // Get the currently selected file info by matching sizes
    var selectedFileInfo: (key: String, size: String, filename: String)? {
        guard let selectedKey = selectedDownloadKey,
              let modelSizes = viewModel.singleModelSearchResult?.modelSize,
              let modelFilenames = viewModel.singleModelSearchResult?.modelFilenames,
              let selectedSize = modelSizes[selectedKey] else {
            return nil
        }
        
        // Find filename that matches the size
        let matchingFilename = modelFilenames.first { (filename, size) in
            size == selectedSize
        }?.key ?? "Unknown"
        
        return (key: selectedKey, size: selectedSize, filename: matchingFilename)
    }
    
    // Helper function to check if a model supports vision
    private func isVisionModel(_ model: ModelInfo) -> Bool {
        return model.tags.contains { tag in
            visionModelTags.contains(tag)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Responsive Header Section
                VStack(spacing: geometry.size.width < 900 ? 12 : 20) {
                    // Title and Description - responsive layout
                    if geometry.size.width < 600 {
                        // Stack vertically on small screens
                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Discover Models")
                                    .font(geometry.size.width < 600 ? .title2 : .largeTitle)
                                    .fontWeight(.bold)
                                    .lineLimit(1)
                                
                                Text("Search and download AI models")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            
                            // Quick stats moved below on small screens with filtering
                            let filteredCount = filterSearchResults(viewModel.searchResults).count
                            if filteredCount > 0 {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(.green)
                                        .frame(width: 6, height: 6)
                                    Text("\(filteredCount) models")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        // Horizontal layout for larger screens
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Discover Models")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text("Search and download AI models from Hugging Face")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            
                            // Quick stats with filtering
                            let filteredCount = filterSearchResults(viewModel.searchResults).count
                            if filteredCount > 0 {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(filteredCount) models found")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(.green)
                                            .frame(width: 6, height: 6)
                                        Text("Live search")
                                            .font(.caption2)
                                            .foregroundStyle(.green)
                                    }
                                }
                            }
                        }
                    }
                
                    // Responsive Search Bar
                    VStack(spacing: 12) {
                        // Main search field
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(isSearchFocused ? .blue : .secondary)
                                .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                            
                            TextField("Search models...", text: $viewModel.query)
                                .focused($isSearchFocused)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .onChange(of: viewModel.query) { _, newValue in
                                    viewModel.searchModels()
                                }
                            
                            if !viewModel.query.isEmpty {
                                Button {
                                    viewModel.query = ""
                                    viewModel.searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isSearchFocused ? .blue.opacity(0.5) : .clear, lineWidth: 2)
                        )
                        .animation(.easeInOut(duration: 0.2), value: isSearchFocused)
                        
                        // Filter toggles
                        HStack(spacing: 20) {
                            Text("Model Types:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                            
                            FilterToggle(
                                title: "MLX",
                                subtitle: "Apple Silicon",
                                icon: "cpu",
                                isOn: $viewModel.isMLX,
                                color: .blue
                            ) {
                                viewModel.searchModels()
                            }
                            
                            FilterToggle(
                                title: "GGUF",
                                subtitle: "CPU & GPU",
                                icon: "memorychip",
                                isOn: $viewModel.isGGUF,
                                color: .green
                            ) {
                                viewModel.searchModels()
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, geometry.size.width < 600 ? 16 : 24)
                .padding(.vertical, geometry.size.width < 600 ? 16 : 20)
                .background(.ultraThickMaterial)
       
                // Main Content Area
                if geometry.size.width < 900 {
                    // Vertical stack for small screens
                    VStack(spacing: 16) {
                        // Search Results Section
                        VStack(spacing: 0) {
                            // Results Content
                            if viewModel.query.isEmpty {
                                VStack(spacing: 20) {
                                    Image(systemName: "magnifyingglass.circle")
                                        .font(.system(size: 48))
                                        .foregroundStyle(.secondary)
                                    
                                    VStack(spacing: 8) {
                                        Text("Discover AI Models")
                                            .font(.title2)
                                            .fontWeight(.semibold)
                                        
                                        Text("Search for thousands of open-source AI models")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 40)
                            } else if viewModel.searchResults.isEmpty {
                                VStack(spacing: 20) {
                                    ProgressView()
                                        .scaleEffect(1.2)
                                    Text("Searching models...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.vertical, 40)
                            } else {
                                List(filterSearchResults(viewModel.searchResults), id: \.id, selection: $selectedModelID) { model in
                                    EnhancedModelPreview(model: model)
                                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                        .listRowBackground(Color.clear)
                                }
                                .onChange(of: selectedModelID) { oldValue, newValue in
                                    if let modelID = newValue {
                                        // Clear previous result and fetch new one
                                        viewModel.singleModelSearchResult = nil
                                        viewModel.searchOneModelInDetail(selectedModelID: modelID)
                                    }
                                }
                                .listStyle(.plain)
                                .scrollContentBackground(.hidden)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        // Model Details Section for small screens
                        if selectedModel != nil {
                            ResponsiveModelDetailsView(
                                selectedModel: selectedModel,
                                viewModel: viewModel,
                                selectedDownloadKey: $selectedDownloadKey,
                                isExpanded: $isExpanded,
                                isCompact: true,
                                geometry: geometry
                            )
                            .frame(maxHeight: geometry.size.height * 0.4)
                        }
                    }
                } else {
                    // Horizontal split for larger screens
                    HSplit(
                        left: {
                            VStack(spacing: 0) {
                                if viewModel.query.isEmpty {
                                    VStack(spacing: 20) {
                                        Image(systemName: "magnifyingglass.circle")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary)
                                        
                                        VStack(spacing: 8) {
                                            Text("Discover AI Models")
                                                .font(.title2)
                                                .fontWeight(.semibold)
                                            
                                            Text("Search for thousands of open-source AI models from Hugging Face")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.vertical, 40)
                                } else if viewModel.searchResults.isEmpty {
                                    VStack(spacing: 20) {
                                        ProgressView()
                                            .scaleEffect(1.2)
                                        Text("Searching models...")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.vertical, 40)
                                } else {
                                    List(filterSearchResults(viewModel.searchResults), id: \.id, selection: $selectedModelID) { model in
                                        EnhancedModelPreview(model: model)
                                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                            .listRowBackground(Color.clear)
                                    }
                                    .onChange(of: selectedModelID) { oldValue, newValue in
                                        if let modelID = newValue {
                                            // Clear previous result and fetch new one
                                            viewModel.singleModelSearchResult = nil
                                            viewModel.searchOneModelInDetail(selectedModelID: modelID)
                                        }
                                    }
                                    .listStyle(.plain)
                                    .scrollContentBackground(.hidden)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        },
                        right: {
                            if selectedModel != nil {
                                ResponsiveModelDetailsView(
                                    selectedModel: selectedModel,
                                    viewModel: viewModel,
                                    selectedDownloadKey: $selectedDownloadKey,
                                    isExpanded: $isExpanded,
                                    isCompact: false,
                                    geometry: geometry
                                )
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            }
                        }
                    )
                    .fraction(0.35)
                    .constraints(minPFraction: 0.3, minSFraction: 0.4)
                    .splitter { 
                        Splitter.invisible()
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func validateModelAccess(_ modelId: String) -> Bool {
        let restrictedPrefixes = ["meta-llama/", "facebook/", "openai/"]
        return !restrictedPrefixes.contains { modelId.hasPrefix($0) }
    }
    
    private func filterSearchResults(_ results: [ModelInfo]) -> [ModelInfo] {
        return results.filter { model in
            // Only filter out clearly problematic repositories - be more permissive
            let problematicPrefixes = ["meta-llama/", "facebook/", "openai/"]
            let isProblematic = problematicPrefixes.contains { model.modelId.hasPrefix($0) }
            return !isProblematic
        }
    }
}

// MARK: - Supporting Views

struct ResponsiveModelDetailsView: View {
    let selectedModel: ModelInfo?
    let viewModel: ModelHubViewModel
    @Binding var selectedDownloadKey: String?
    @Binding var isExpanded: Bool
    let isCompact: Bool
    let geometry: GeometryProxy
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 12 : 16) {
                if let model = selectedModel {
                    // Model Header Card
                    ModelHeaderCard(model: model, isCompact: isCompact)
                    
                    // Download Options Section - MOVED TO TOP for visibility
                    if let sizes = viewModel.singleModelSearchResult?.modelSize,
                       !sizes.isEmpty {
                        DownloadOptionsSection(
                            modelSizes: sizes,
                            modelFilenames: viewModel.singleModelSearchResult?.modelFilenames ?? [:],
                            selectedDownloadKey: $selectedDownloadKey,
                            onDownload: { key, size, filename in
                                startModelDownload(modelId: model.modelId, size: size, filename: filename)
                            },
                            isCompact: isCompact,
                            modelId: model.modelId
                        )
                        .environmentObject(viewModel)
                    } else {
                        // Loading state while fetching model details
                        if viewModel.singleModelSearchResult == nil {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading model details...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // README Section - moved below download options
                    if let readme = viewModel.singleModelSearchResult?.readme, !readme.isEmpty {
                        ReadmeSection(content: readme, isCompact: isCompact)
                    }
                }
            }
            .padding(isCompact ? 8 : 12)
        }
    }
    
    private func startModelDownload(modelId: String, size: String, filename: String) {
        // Determine model type based on filename
        let modelType = filename.hasSuffix(".gguf") ? "gguf" : "mlx"
        
        // For MLX models, pass empty files array (downloads entire model)
        // For GGUF models, pass specific filename
        let filesToDownload: [String] = modelType == "mlx" ? [] : [filename]
        
        // Start download using the existing viewModel method
        viewModel.startDownload(modelId: modelId, modelType: modelType, files: filesToDownload)
        
        // Generate unique ID for tracking
        let uniqueId = viewModel.generateUniqueId(modelId: modelId, modelType: modelType, files: filesToDownload)
        
        print("Started download for \(modelId) - \(filename) (\(size))")
        print("Model type: \(modelType)")
        print("Files: \(filesToDownload)")
        print("Unique ID: \(uniqueId)")
        
        // Clear selection after starting download
        selectedDownloadKey = nil
    }
}

struct ModelHeaderCard: View {
    let model: ModelInfo
    let isCompact: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title and Type Badge
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.modelName)
                        .font(isCompact ? .headline : .title2)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                    
                    Text("by \(model.author)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Text(model.modelType?.uppercased() ?? "UNKNOWN")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.15))
                    .foregroundStyle(.blue)
                    .clipShape(Capsule())
            }
            
            // Repository Info
            HStack(spacing: 4) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.modelId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            // Statistics
            HStack(spacing: isCompact ? 12 : 20) {
                StatItem(icon: "heart.fill", value: formatNumber(model.likes ?? 0), color: .red)
                StatItem(icon: "arrow.down.circle.fill", value: formatNumber(model.downloads ?? 0), color: .blue)
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(model.lastModified ?? "Never")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}

struct StatItem: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

struct ReadmeSection: View {
    let content: String
    let isCompact: Bool
    @State private var isExpanded = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("README", systemImage: "doc.text")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isExpanded.toggle()
                    }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
            
            if content != "No README available" && content != "README not available" {
                VStack(alignment: .leading) {
                    Markdown(content)
                        .markdownTextStyle(\.text) {
                            FontSize(isCompact ? 13 : 14)
                        }
                        .markdownTextStyle(\.code) {
                            FontFamilyVariant(.monospaced)
                            BackgroundColor(.secondary.opacity(0.1))
                        }
                        .lineLimit(isExpanded ? nil : 10)
                        .clipped()
                }
                .frame(maxHeight: isExpanded ? .infinity : 200)
            } else {
                Text("No README available for this model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}

struct DownloadOptionsSection: View {
    let modelSizes: [String: String]
    let modelFilenames: [String: String]
    @Binding var selectedDownloadKey: String?
    let onDownload: (String, String, String) -> Void
    let isCompact: Bool
    let modelId: String // Add modelId parameter
    @EnvironmentObject var viewModel: ModelHubViewModel
    
    // Helper function to extract quantization type from filename
    private func extractQuantizationType(from filename: String) -> String {
        // Remove .gguf extension and extract quantization
        let name = filename.replacingOccurrences(of: ".gguf", with: "")
        let parts = name.components(separatedBy: "-")
        
        // Look for quantization patterns in reverse order
        for part in parts.reversed() {
            if part.contains("Q") || part.contains("IQ") || part.contains("K") {
                return part
            }
        }
        
        // Fallback: use last part or "Standard"
        return parts.last ?? "Standard"
    }
    
    // Helper function to format file size from bytes string
    private func formatFileSize(_ sizeString: String) -> String {
        guard let bytes = Int64(sizeString) else { return sizeString }
        
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Count total available options
    private var totalOptionsCount: Int {
        if !modelFilenames.isEmpty {
            return modelFilenames.count
        } else {
            return modelSizes.count
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Enhanced header with prominence
            HStack {
                Label("Download Options", systemImage: "arrow.down.circle.fill")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
                
                Spacer()
                
                Text("\(totalOptionsCount) option\(totalOptionsCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            VStack(spacing: 12) {
                // For GGUF models, iterate over actual filenames
                ForEach(Array(modelFilenames.keys.sorted()), id: \.self) { filename in
                    if let size = modelFilenames[filename] {
                        let humanReadableSize = formatFileSize(size)
                        DownloadOptionRow(
                            key: extractQuantizationType(from: filename),
                            size: humanReadableSize,
                            filename: filename,
                            isSelected: selectedDownloadKey == filename,
                            onSelect: { selectedDownloadKey = filename },
                            onDownload: { onDownload(extractQuantizationType(from: filename), size, filename) },
                            isCompact: isCompact,
                            viewModel: viewModel,
                            modelId: modelId
                        )
                    }
                }
                
                // Fallback: If no filenames but have model sizes (MLX case)
                if modelFilenames.isEmpty && !modelSizes.isEmpty {
                    ForEach(Array(modelSizes.keys.sorted()), id: \.self) { key in
                        if let size = modelSizes[key] {
                            let humanReadableSize = formatFileSize(size)
                            DownloadOptionRow(
                                key: key,
                                size: humanReadableSize,
                                filename: "mlx-files", // MLX downloads entire model
                                isSelected: selectedDownloadKey == key,
                                onSelect: { selectedDownloadKey = key },
                                onDownload: { onDownload(key, size, "mlx-files") },
                                isCompact: isCompact,
                                viewModel: viewModel,
                                modelId: modelId
                            )
                        }
                    }
                }
            }
            
        }
        .padding(16)
        .background(.blue.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.blue.opacity(0.2), lineWidth: 1)
        )
        
    }
}

struct DownloadOptionRow: View {
    let key: String
    let size: String
    let filename: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let isCompact: Bool
    let viewModel: ModelHubViewModel
    let modelId: String? // Add modelId for proper status tracking
    
    @State private var pulseScale: Double = 1.0
    
    // Extract quantization type from filename
    private var quantizationType: String {
        // Extract quantization from filename (e.g., "Q4_K_M.gguf" -> "Q4_K_M")
        let name = filename.replacingOccurrences(of: ".gguf", with: "")
        let parts = name.components(separatedBy: "-")
        
        // Look for quantization patterns
        for part in parts.reversed() {
            if part.contains("Q") || part.contains("IQ") || part.contains("K") {
                return part
            }
        }
        
        // Fallback: use the key or last part
        return key.isEmpty ? parts.last ?? "Standard" : key
    }
    
    // Get download status for this specific file
    private var downloadStatus: (isDownloading: Bool, isComplete: Bool, progress: Double) {
        let modelType = filename.hasSuffix(".gguf") ? "gguf" : "mlx"
        
        // Generate the expected unique ID for this download
        let expectedUniqueId: String
        if let modelId = modelId {
            if modelType == "gguf" {
                // For GGUF: author/quantization (e.g., "microsoft/Q4_K_M")
                let modelAuthor = modelId.split(separator: "/").first ?? ""
                let quantization = key // The quantization type we extracted
                expectedUniqueId = "\(modelAuthor)/\(quantization)"
            } else {
                // For MLX: use full model ID (e.g., "microsoft/DialoGPT-medium")
                expectedUniqueId = modelId
            }
        } else {
            // Fallback to filename matching
            expectedUniqueId = filename.replacingOccurrences(of: ".gguf", with: "")
        }
        
        // Check download status using the expected unique ID
        let isDownloading = viewModel.downloadingModels.contains { download in
            download.status == "downloading" && (
                download.id == expectedUniqueId ||
                download.id.contains(expectedUniqueId) ||
                expectedUniqueId.contains(download.id)
            )
        }
        
        let isComplete = viewModel.downloadedModels.contains { download in
            download.status == "ready" && (
                download.id == expectedUniqueId ||
                download.id.contains(expectedUniqueId) ||
                expectedUniqueId.contains(download.id)
            )
        }
        
        // Find progress using the expected unique ID
        var progress = 0.0
        for (uniqueId, progressValue) in viewModel.downloadProgress {
            if uniqueId == expectedUniqueId ||
               uniqueId.contains(expectedUniqueId) ||
               expectedUniqueId.contains(uniqueId) {
                progress = progressValue
                break
            }
        }
        
        return (isDownloading, isComplete, progress)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // Status indicator icon
                Group {
                    if downloadStatus.isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if downloadStatus.isDownloading {
                        if #available(macOS 15.0, *) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .symbolEffect(.pulse)
                        } else {
                            // Fallback for macOS 14: Custom pulse animation
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(.blue)
                                .scaleEffect(pulseScale)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                                        pulseScale = 1.2
                                    }
                                }
                        }
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(.gray)
                    }
                }
                .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Quantization type as primary label
                    Text(quantizationType)
                        .font(isCompact ? .headline : .title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    // Filename as secondary info
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    // Size badge with enhanced styling
                    Text(size)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                    
                    // Download status text
                    if downloadStatus.isComplete {
                        Text("Downloaded")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    } else if downloadStatus.isDownloading {
                        Text(String(format: "%.0f%%", downloadStatus.progress * 100))
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                
                // Enhanced download button with status awareness
                Button {
                    if !downloadStatus.isDownloading {
                        onDownload()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if downloadStatus.isComplete {
                            Image(systemName: "checkmark")
                            Text("Ready")
                        } else if downloadStatus.isDownloading {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Downloading")
                        } else {
                            Image(systemName: "square.and.arrow.down")
                            Text("Download")
                        }
                    }
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(downloadStatus.isDownloading || downloadStatus.isComplete)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Progress bar for downloading files
            if downloadStatus.isDownloading {
                ProgressView(value: downloadStatus.progress)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .background(
            downloadStatus.isComplete ? .green.opacity(0.05) :
            downloadStatus.isDownloading ? .blue.opacity(0.05) :
            isSelected ? .blue.opacity(0.08) : .white.opacity(0.1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    downloadStatus.isComplete ? .green.opacity(0.3) :
                    downloadStatus.isDownloading ? .blue.opacity(0.5) :
                    isSelected ? .blue.opacity(0.4) : .gray.opacity(0.2),
                    lineWidth: isSelected || downloadStatus.isDownloading ? 2 : 1
                )
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        .onTapGesture {
            if !downloadStatus.isDownloading {
                onSelect()
            }
        }
    }
}

struct FilterToggle: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let color: Color
    let onChange: () -> Void
    
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isOn.toggle()
                onChange()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn ? color : .secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(isOn ? .primary : .secondary)
                    
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? color : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isOn ? color.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isOn ? color.opacity(0.3) : .secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isOn)
    }
}

struct EnhancedModelPreview: View {
    let model: ModelInfo
    
    // Vision model tags for checking
    private let visionModelTags = [
        "image-to-text", "image-classification", "visual-question-answering",
        "image-text-to-text", "image-segmentation", "object-detection",
        "zero-shot-image-classification", "image-feature-extraction"
    ]
    
    // Helper function to check if model supports vision
    private func isVisionModel() -> Bool {
        return model.tags.contains { tag in
            visionModelTags.contains(tag)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Model icon/logo
                VStack {
                    Image("hf-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Model info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 8) {
                            Text(model.modelName)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            
                            // Vision indicator
                            if isVisionModel() {
                                Image(systemName: "eye.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.purple)
                                    .help("Vision-Language Model")
                            }
                        }
                        
                        Spacer()
                        
                        // Model type badge with vision coloring
                        Text(model.modelType ?? "Unknown")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .textCase(.uppercase)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isVisionModel() ? .purple.opacity(0.8) : .blue.opacity(0.8))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    
                    // Author
                    Text(model.author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    
                    // Stats row
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "heart")
                                .font(.caption2)
                                .foregroundStyle(.red)
                            Text("\(model.likes ?? 0)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Text("\(formatNumber(model.downloads ?? 0))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(model.lastModified ?? "Never")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.quaternary, lineWidth: 0.5)
        )
    }
}

func formatNumber(_ number: Int) -> String {
    if number >= 1000000 {
        return String(format: "%.1fM", Double(number) / 1000000)
    } else if number >= 1000 {
        return String(format: "%.1fK", Double(number) / 1000)
    } else {
        return "\(number)"
    }
}

// Legacy components for compatibility
func copyToClipboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

func getTotalMemoryInGB() -> Int64 {
    var size: Int64 = 0
    var len = MemoryLayout<Int64>.size
    sysctlbyname("hw.memsize", &size, &len, nil, 0)
    return Int64(size)
}

func humanReadableSize(bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useGB, .useMB, .useKB]
    formatter.countStyle = .decimal
    return formatter.string(fromByteCount: bytes)
}

#Preview {
    ModelHubView()
}
