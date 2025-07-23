//
//  ModelHubRoutes.swift
//  SuriAI
//
//  Created by Pradhumn Gupta on 24/06/25.
//

import SwiftUI

struct ModelInfo: Identifiable, Codable, Hashable {
    var id: String { modelId }
    let modelId: String
    let tags: [String]
    let downloads: Int?
    let likes: Int?
    let lastModified: String?
    let author: String
    let modelName: String
    let modelType: String?
    
    enum CodingKeys: String, CodingKey {
        case modelId
        case tags
        case downloads
        case likes
        case lastModified
        case author
        case modelName
        case modelType
    }
}

struct APIModelInfo: Identifiable, Codable, Hashable {
    var id: String { modelId }
    let modelId: String
    let modelType: String
    let modelSource: String
    let provider: String
    let engine: String
    let available: Bool
    let isImageModel: Bool
    let supportsText: Bool
    let capabilities: [String]
    
    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case modelType = "model_type"
        case modelSource = "model_source"
        case provider
        case engine
        case available
        case isImageModel = "is_image_model"
        case supportsText = "supports_text"
        case capabilities
    }
}

struct VisionModelInfo: Identifiable, Codable, Hashable {
    var id: String { modelId }
    let modelId: String
    let name: String
    let description: String
    let size: String
    let recommended: Bool
    let isLocal: Bool
    let isLoaded: Bool
    let status: String
    let fullModelName: String?
    
    enum CodingKeys: String, CodingKey {
        case modelId = "id"
        case name
        case description
        case size
        case recommended
        case isLocal = "is_local"
        case isLoaded = "is_loaded"
        case status
        case fullModelName = "full_model_name"
    }
}

struct SingleModelInfo: Codable, Hashable {
    let modelId: String
    let modelSize: [String: String]?
    let modelFilenames: [String: String]?
    let readme: String?
    
    enum CodingKeys: String, CodingKey {
        case modelId
        case modelSize
        case modelFilenames
        case readme
    }
}

class ModelHubViewModel: ObservableObject {
    @Published var query = ""
    @Published var searchResults: [ModelInfo] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadedModels: [DownloadInfo] = []
    @Published var downloadingModels: [DownloadInfo] = []
    @Published var apiModels: [APIModelInfo] = []
    @Published var singleModelSearchResult: SingleModelInfo? = nil
    @Published var currentSelectedModelID: String? = nil
    @Published var pausedModels: [DownloadInfo] = []
    @Published var errorModels: [DownloadInfo] = []
    @Published var isMLX: Bool = true
    @Published var isGGUF: Bool = true
    @Published var isLoading: Bool = false
    @Published var errorMessage: String = ""
    @Published var isSwitchingModel: Bool = false
    @Published var modelsDirectory: String = ""
    @Published var isChangingDirectory: Bool = false
    @Published var visionModels: [VisionModelInfo] = []
    @Published var currentVisionModel: String? = nil
    @Published var isVisionModelLoaded: Bool = false
    
    // Add model manager for unified API integration
    private let modelManager = ModelManager()
    

    var baseURL: String {
        return serverConfig.currentServerURL
    }
    lazy var downloadURL: String = {
        return baseURL + "/downloads"
    }()
    lazy var searchURL: String = {
        return baseURL + "/search"
    }()
    private var downloadTimers: [String: Timer] = [:]
    
    func generateUniqueId(modelId: String, modelType: String, files: [String]) -> String {
            if modelType == "gguf" && files.count == 1 {
                // For GGUF files, use model_id + filename (without extension) for uniqueness
                let fileName = files[0]
                let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
                let modelAuthor = modelId.split(separator: "/").first ?? ""
                return "\(modelAuthor)/\(baseName)"
            } else {
                // For MLX or multi-file downloads, use the model_id as-is
                return modelId
            }
        }
    

    func searchModels() {
        print("Searching")
        var model_type = "all"
        if !self.isMLX {
            model_type = "gguf"
        }
        else if !self.isGGUF {
            model_type = "mlx"
        }
        else {
            model_type = "all"
        }
        
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(searchURL)/search_models?query=\(encodedQuery)&model_type=\(model_type)") else {
            print("Invalid URL")
            return
        }

        print("Searched with URL: \(url)")

        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("Network error: \(error)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let results = try JSONDecoder().decode([ModelInfo].self, from: data)
                print("Decoded results: \(results)")
                DispatchQueue.main.async {
                    
                    if !self.isMLX && !self.isGGUF {
                        self.searchResults = []
                    }
                    else{
                        self.searchResults = results
                    }
                    
                    
                }
            } catch {
                print("Decoding error: \(error)")
                print("Raw data: \(String(data: data, encoding: .utf8) ?? "Unreadable")")
            }
        }.resume()
        
    }
    
    func searchOneModelInDetail(selectedModelID: String) {
        print("Searching One Model")
        print("Selected Model ID:",selectedModelID)
        
        guard let url = URL(string: "\(searchURL)/search_one_model_in_detail")else {
            print("Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = ["model_id": selectedModelID]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("JSON error: \(error)")
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                print("Network error: \(error)")
                return
            }
            
            guard let data = data else {
                print("No data received")
                return
            }
            
            do {
                let result = try JSONDecoder().decode(SingleModelInfo.self, from: data)
//                print("Decoded result: \(result)")
                DispatchQueue.main.async {
                    self.singleModelSearchResult = result  // wrap in array if you're expecting single result
                    print(selectedModelID)
                    print(self.singleModelSearchResult?.modelSize ?? "novalue")
                    let size = self.singleModelSearchResult?.modelSize?[selectedModelID] ?? "No model size"
                    print("Model size: \(size)")
                }
            } catch {
                print("Decoding error: \(error)")
                print("Raw data: \(String(data: data, encoding: .utf8) ?? "Unreadable")")
            }
        }.resume()

        
    }


    // MARK: - Download Management Functions
        func startDownload(modelId: String, modelType: String, files: [String] = []) {
            print("Starting download for: \(modelId)")
            
            guard let url = URL(string: "\(downloadURL)/download_model") else {
                errorMessage = "Invalid URL"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload: [String: Any] = [
                "model_id": modelId,
                "model_type": modelType,
                "files": files
            ]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            } catch {
                errorMessage = "Failed to encode request"
                return
            }
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to start download: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let data = data else {
                    DispatchQueue.main.async {
                        self.errorMessage = "No response data"
                    }
                    return
                }
                
                do {
                    if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let status = result["status"] as? String {
                            print("Download status: \(status)")
                            DispatchQueue.main.async {
                                // Generate unique ID to start polling
                                let uniqueId = self.generateUniqueId(modelId: modelId, modelType: modelType, files: files)
                                self.startPollingProgress(for: uniqueId)
                                Task { await self.fetchDownloadedModels() }
                            }
                        } else if let error = result["error"] as? String {
                            DispatchQueue.main.async {
                                self.errorMessage = "Download error: \(error)"
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to parse response"
                    }
                }
            }.resume()
        }
        
        func pauseDownload(uniqueId: String) {
            print("Pausing download for: \(uniqueId)")
            
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/pause_download?unique_id=\(encodedUniqueId)") else {
                errorMessage = "Invalid URL"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to pause download: \(error.localizedDescription)"
                    }
                    return
                }
                
                // Stop polling for this model
                DispatchQueue.main.async {
                    self.stopPollingProgress(for: uniqueId)
                    Task { await self.fetchDownloadedModels() }
                }
            }.resume()
        }
        
        func resumeDownload(uniqueId: String) {
            print("Resuming download for: \(uniqueId)")
            
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/resume_download?unique_id=\(encodedUniqueId)") else {
                errorMessage = "Invalid URL"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to resume download: \(error.localizedDescription)"
                    }
                    return
                }
                
                // Start polling again
                DispatchQueue.main.async {
                    self.startPollingProgress(for: uniqueId)
                    Task { await self.fetchDownloadedModels() }
                }
            }.resume()
        }
        
        func cancelDownload(uniqueId: String) {
            print("Cancelling download for: \(uniqueId)")
            
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/cancel_download?unique_id=\(encodedUniqueId)") else {
                errorMessage = "Invalid URL"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to cancel download: \(error.localizedDescription)"
                    }
                    return
                }
                
                // Stop polling for this model
                DispatchQueue.main.async {
                    self.stopPollingProgress(for: uniqueId)
                    Task { await self.fetchDownloadedModels() }
                }
            }.resume()
        }
        
        func deleteModel(uniqueId: String) {
            print("Deleting model: \(uniqueId)")
            
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/delete_model?unique_id=\(encodedUniqueId)") else {
                errorMessage = "Invalid URL"
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to delete model: \(error.localizedDescription)"
                    }
                    return
                }
                
                DispatchQueue.main.async {
                    self.stopPollingProgress(for: uniqueId)
                    Task { await self.fetchDownloadedModels() }
                }
            }.resume()
        }
        
        // MARK: - Progress Monitoring
        func startPollingProgress(for uniqueId: String) {
            // Stop existing timer if any
            stopPollingProgress(for: uniqueId)
            
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                self.fetchProgress(for: uniqueId)
            }
            
            downloadTimers[uniqueId] = timer
        }
        
        func stopPollingProgress(for uniqueId: String) {
            downloadTimers[uniqueId]?.invalidate()
            downloadTimers.removeValue(forKey: uniqueId)
        }
        
        func fetchProgress(for uniqueId: String) {
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/progress?unique_id=\(encodedUniqueId)") else {
                return
            }
            
            URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                
                if let downloaded = json["downloaded"] as? Double,
                   let total = json["total"] as? Double,
                   total > 0 {
                    DispatchQueue.main.async {
                        let progress = downloaded / total
                        self.downloadProgress[uniqueId] = progress
                        
                        // Stop polling if download is complete
                        if downloaded >= total {
                            self.stopPollingProgress(for: uniqueId)
                            Task { await self.fetchDownloadedModels() }
                        }
                    }
                }
            }.resume()
        }
        
        // MARK: - List Functions
        func fetchDownloadedModels() async {
            guard let url = URL(string: "\(downloadURL)/downloads") else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let response = try decoder.decode(DownloadResponse.self, from: data)
                
                let allModels: [DownloadInfo] = response.downloads.compactMap { key, value in
                    var copy = value
                    copy.id = key // This is now the unique_id
                    return copy
                }
                
                await MainActor.run {
                    downloadedModels = allModels
                        .filter { $0.status == "ready" }
                        .sorted { $0.id < $1.id }
                    
                    downloadingModels = allModels
                        .filter { $0.status == "downloading" || $0.status == "paused" || $0.status == "error" }
                        .sorted { $0.id < $1.id }
                    
                    pausedModels = allModels
                        .filter { $0.status == "paused" }
                        .sorted { $0.id < $1.id }
                    
                    errorModels = allModels
                        .filter { $0.status == "error" }
                        .sorted { $0.id < $1.id }
                    
                    // Start polling for downloading models
                    for model in downloadingModels {
                        if downloadTimers[model.id] == nil {
                            startPollingProgress(for: model.id)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to fetch downloads: \(error.localizedDescription)"
                }
            }
        }
        
        func fetchAPIModels() async {
            guard let url = URL(string: "\(baseURL)/models") else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                // Parse JSON response manually to extract models array
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = jsonObject["models"] as? [[String: Any]] {
                    
                    let apiModelsList: [APIModelInfo] = models.compactMap { modelDict in
                        guard let modelSource = modelDict["model_source"] as? String,
                              modelSource == "api",
                              let modelId = modelDict["model_id"] as? String,
                              let modelType = modelDict["model_type"] as? String,
                              let provider = modelDict["provider"] as? String,
                              let engine = modelDict["engine"] as? String,
                              let available = modelDict["available"] as? Bool else {
                            return nil
                        }
                        
                        // Extract image model capabilities
                        let isImageModel = modelDict["is_image_model"] as? Bool ?? false
                        let supportsText = modelDict["supports_text"] as? Bool ?? true
                        let capabilities = modelDict["capabilities"] as? [String] ?? []
                        
                        return APIModelInfo(
                            modelId: modelId,
                            modelType: modelType,
                            modelSource: modelSource,
                            provider: provider,
                            engine: engine,
                            available: available,
                            isImageModel: isImageModel,
                            supportsText: supportsText,
                            capabilities: capabilities
                        )
                    }
                    
                    await MainActor.run {
                        self.apiModels = apiModelsList
                    }
                }
            } catch {
                await MainActor.run {
                    print("Failed to fetch API models: \(error.localizedDescription)")
                }
            }
        }
        
        func getDownloadStatus(for uniqueId: String) async -> DownloadStatusInfo? {
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/download_status/\(encodedUniqueId)") else {
                return nil
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                return try decoder.decode(DownloadStatusInfo.self, from: data)
            } catch {
                print("Failed to get download status: \(error)")
                return nil
            }
        }
        
        func getModelStatus(for uniqueId: String) async -> ModelStatus? {
            guard let encodedUniqueId = uniqueId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "\(downloadURL)/model_status/\(encodedUniqueId)") else {
                return nil
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoder = JSONDecoder()
                return try decoder.decode(ModelStatus.self, from: data)
            } catch {
                print("Failed to get model status: \(error)")
                return nil
            }
        }
        
        // MARK: - Utility Functions
        func clearError() {
            errorMessage = ""
        }
        
        func refreshAll() async {
            await fetchDownloadedModels()
            await fetchAPIModels()
            await fetchModelsDirectory()
        }
        
        // MARK: - Models Directory Management
        func fetchModelsDirectory() async {
            guard let url = URL(string: "\(downloadURL)/models_directory") else { return }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let directory = jsonObject["models_directory"] as? String {
                    
                    await MainActor.run {
                        self.modelsDirectory = directory
                    }
                }
            } catch {
                await MainActor.run {
                    print("Failed to fetch models directory: \(error.localizedDescription)")
                }
            }
        }
        
        func setModelsDirectory(newPath: String) async -> Bool {
            await MainActor.run {
                self.isChangingDirectory = true
                self.errorMessage = ""
            }
            
            guard let url = URL(string: "\(downloadURL)/models_directory") else {
                await MainActor.run {
                    self.isChangingDirectory = false
                    self.errorMessage = "Invalid URL"
                }
                return false
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let payload = ["new_path": newPath]
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: payload)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let directory = jsonObject["models_directory"] as? String {
                            
                            await MainActor.run {
                                self.modelsDirectory = directory
                                self.isChangingDirectory = false
                                self.errorMessage = ""
                            }
                            return true
                        }
                    } else {
                        // Handle error response
                        if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = jsonObject["error"] as? String {
                            
                            await MainActor.run {
                                self.errorMessage = error
                                self.isChangingDirectory = false
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to change models directory: \(error.localizedDescription)"
                    self.isChangingDirectory = false
                }
            }
            
            return false
        }
        
        // MARK: - Model Switching Functions
        func switchToModel(modelId: String) async {
            await MainActor.run {
                self.isSwitchingModel = true
                self.errorMessage = ""
            }
            
            // Use the model manager to switch models
            let success = await modelManager.switchModel(modelId: modelId)
            
            await MainActor.run {
                if success {
                    self.currentSelectedModelID = modelId
                    self.errorMessage = ""
                } else {
                    self.errorMessage = modelManager.errorMessage
                }
                self.isSwitchingModel = false
            }
        }
        
        func getCurrentModelStatus() async {
            await modelManager.checkServerStatus()
            
            await MainActor.run {
                self.currentSelectedModelID = modelManager.currentModel?.model_id
            }
        }
        
        // MARK: - Vision Model Management
        func fetchVisionModels() async {
            guard let url = URL(string: "\(baseURL)/vision_models") else {
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("Vision models response: \(jsonString)")
                }
                
                let response = try JSONDecoder().decode([VisionModelInfo].self, from: data)
                
                await MainActor.run {
                    self.visionModels = response
                }
            } catch {
                print("Error fetching vision models: \(error)")
                await MainActor.run {
                    self.visionModels = []
                }
            }
        }
        
        func fetchVisionModelStatus() async {
            guard let url = URL(string: "\(baseURL)/vision_models/status") else {
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(VisionModelStatus.self, from: data)
                
                await MainActor.run {
                    self.isVisionModelLoaded = response.modelLoaded
                    self.currentVisionModel = response.currentModel
                }
            } catch {
                print("Error fetching vision model status: \(error)")
            }
        }
        
        func loadVisionModel(modelKey: String) async {
            guard let url = URL(string: "\(baseURL)/vision_models/\(modelKey)/load") else {
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(VisionModelLoadResponse.self, from: data)
                
                if response.success {
                    await MainActor.run {
                        self.currentVisionModel = response.currentModel
                        self.isVisionModelLoaded = true
                    }
                    
                    // Refresh vision models list
                    await fetchVisionModels()
                }
            } catch {
                print("Error loading vision model: \(error)")
            }
        }
        
        func unloadVisionModel() async {
            guard let url = URL(string: "\(baseURL)/vision_models/unload") else {
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(VisionModelUnloadResponse.self, from: data)
                
                if response.success {
                    await MainActor.run {
                        self.currentVisionModel = nil
                        self.isVisionModelLoaded = false
                    }
                    
                    // Refresh vision models list
                    await fetchVisionModels()
                }
            } catch {
                print("Error unloading vision model: \(error)")
            }
        }
        
        deinit {
            // Clean up timers
            for timer in downloadTimers.values {
                timer.invalidate()
            }
        }


    }

    struct ModelDetail: Codable {
        let modelId: String
        let description: String?
        let license: String?
        let author: String?
        let tags: [String]
        let downloads: Int?
        let likes: Int?
        let lastModified: String?
    }

    struct VisionModelStatus: Codable {
        let modelLoaded: Bool
        let currentModel: String?
        let sparrowAvailable: Bool
        
        enum CodingKeys: String, CodingKey {
            case modelLoaded = "model_loaded"
            case currentModel = "current_model"
            case sparrowAvailable = "sparrow_available"
        }
    }

    struct VisionModelLoadResponse: Codable {
        let success: Bool
        let message: String
        let currentModel: String?
        
        enum CodingKeys: String, CodingKey {
            case success
            case message
            case currentModel = "current_model"
        }
    }

    struct VisionModelUnloadResponse: Codable {
        let success: Bool
        let message: String
    }

    struct DownloadInfo: Codable, Identifiable {
        var id: String = UUID().uuidString // This will be the unique_id from the server
        let modelId: String? // Add this to store the original model_id
        let uniqueId: String? // Add this to store the unique_id
        let downloaded: Int
        let total: Int
        let status: String
        let percentage: Double
        let createdAt: String?
        let updatedAt: String?
        
        enum CodingKeys: String, CodingKey {
            case modelId = "model_id"
            case uniqueId = "unique_id"
            case downloaded, total, status, percentage
            case createdAt = "created_at"
            case updatedAt = "updated_at"
        }
    }

    struct DownloadResponse: Codable {
        let downloads: [String: DownloadInfo]
        let totalDownloads: Int?
        
        enum CodingKeys: String, CodingKey {
            case downloads
            case totalDownloads = "total_downloads"
        }
    }

    struct DownloadStatusInfo: Codable {
        let modelId: String
        let uniqueId: String
        let modelType: String
        let files: [String]
        let downloaded: Int
        let total: Int
        let status: String
        let percentage: Double
        let isPaused: Bool
        let isCancelled: Bool
        let createdAt: String
        let updatedAt: String
        let fileProgress: [String: FileProgress]?
        let error: String?
        
        enum CodingKeys: String, CodingKey {
            case modelId = "model_id"
            case uniqueId = "unique_id"
            case modelType = "model_type"
            case files, downloaded, total, status, percentage
            case isPaused = "is_paused"
            case isCancelled = "is_cancelled"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case fileProgress = "file_progress"
            case error
        }
    }

    struct FileProgress: Codable {
        let downloaded: Int
        let totalSize: Int
        let complete: Bool
        let url: String?
        
        enum CodingKeys: String, CodingKey {
            case downloaded
            case totalSize = "total_size"
            case complete
            case url
        }
    }

    struct ModelStatus: Codable {
        let modelId: String
        let uniqueId: String
        let status: String
        let modelPath: String
        let absolutePath: String  // Add this new field
        let exists: Bool
        let isComplete: Bool
        let createdAt: String
        let updatedAt: String
        let files: [String]  // Add this new field
        
        enum CodingKeys: String, CodingKey {
            case modelId = "model_id"
            case uniqueId = "unique_id"
            case status
            case modelPath = "model_path"
            case absolutePath = "absolute_path"  // Add this
            case exists
            case isComplete = "is_complete"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case files  // Add this
        }
    }

    struct LontentView: View {
        @StateObject private var vm = ModelHubViewModel()
        
        var body: some View {
            VStack(spacing:0) {
                
                Text("Downloading Models")
                    .padding(10)
                HStack{
                    Button{
                        vm.startDownload(modelId: "unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF",modelType: "gguf",files:["DeepSeek-R1-0528-Qwen3-8B-UD-IQ1_M.gguf"])
                    }label: {
                        Text("Start Download")
                    }
                    Button{
                        // Generate the unique ID for this specific file
                        let uniqueId = vm.generateUniqueId(
                            modelId: "unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF",
                            modelType: "gguf",
                            files: ["DeepSeek-R1-0528-Qwen3-8B-UD-IQ1_M.gguf"]
                        )
                        vm.pauseDownload(uniqueId: uniqueId)
                    }label: {
                        Text("Pause")
                    }
                    Button{
                        // Generate the unique ID for this specific file
                        let uniqueId = vm.generateUniqueId(
                            modelId: "unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF",
                            modelType: "gguf",
                            files: ["DeepSeek-R1-0528-Qwen3-8B-UD-IQ1_M.gguf"]
                        )
                        vm.resumeDownload(uniqueId: uniqueId)
                    }label: {
                        Text("Resume")
                    }

                    Button{
                        // Generate the unique ID for this specific file
                        let uniqueId = vm.generateUniqueId(
                            modelId: "unsloth/DeepSeek-R1-0528-Qwen3-8B-GGUF",
                            modelType: "gguf",
                            files: ["DeepSeek-R1-0528-Qwen3-8B-UD-IQ1_M.gguf"]
                        )
                        vm.deleteModel(uniqueId: uniqueId)
                    }label: {
                        Text("Delete")
                    }
                }
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
                .frame(maxHeight: .infinity)
                .onAppear{
                    
                }
                
                Text("My Models")
                    .padding(10)
                
                List(vm.downloadedModels) { model in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(model.id).font(.headline).lineLimit(1)
                            Spacer()
                            Text(model.status).font(.subheadline).foregroundColor(.secondary)
                        }
                        ProgressView(value: model.percentage / 100)
                            .progressViewStyle(.linear)
                        Text(String(format: "%.2f %%", model.percentage))
                            .font(.caption).foregroundColor(.secondary)
                        
                        // Add delete button for completed downloads
                        HStack {
                            Spacer()
                            Button("Delete") {
                                vm.deleteModel(uniqueId: model.id)
                            }
                            .foregroundColor(.red)
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                
            }
            .navigationTitle("Downloads")
            .onAppear{
                Task {
                    await vm.fetchDownloadedModels()
                }
            }

        }
    }

    #Preview {
        LontentView()
    }
