//import SwiftUI
//
//struct Message: Encodable {
//    let input : String
//}
//struct ModelMessage: Decodable {
//    let response : String
//}
//
//func sendPostRequest (userInput: String!) async -> String {
//    
//    
//    let url = URL(string: "http://127.0.0.1:8001/chat")!
//    
//    var request = URLRequest(url: url)
//    request.httpMethod = "POST"
//    
////
//    let message = Message(input: userInput)
//    
////
////
//    let jsonData = try! JSONEncoder().encode(message)
//    
//    request.httpBody = jsonData
//    
//    
//    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
////
//    do{
//        let (data, _) = try await URLSession.shared.upload(for: request, from: jsonData)
//        let newData = try JSONDecoder().decode(ModelMessage.self,from: data)
//        print(newData)
//        return newData.response
//
//    }catch{
//        print("Fetch Failed, Error: ",error)
//        return "Fetch Failed"
//    }
//    
//}

import Foundation
import SwiftUI

// Your message to send
struct Message: Encodable {
    let input: String
}

// The JSON response chunk you expect from the server, e.g. {"content": "..."}
struct ModelMessage: Decodable {
    let content: String
}

func streamChatResponse(userInput: String) async throws -> AsyncThrowingStream<String, Error> {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/chat")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let message = Message(input: userInput)
    request.httpBody = try JSONEncoder().encode(message)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    guard line.starts(with: "data:") else { continue }
                    print(line)
                    let dataLine = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // Stop signal (optional)
                    if dataLine == "[DONE]" || dataLine == "<|eot_id|>" {
                        break
                    }
                    
                    if let jsonData = dataLine.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ModelMessage.self, from: jsonData) {
                        continuation.yield(decoded.content)
                    }
                    
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func streamChatHistoryResponse(inputText: String, chatId: String) async throws -> AsyncThrowingStream<String, Error> {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/chat_history_stream")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let requestBody = [
        "user_id": "default_user",
        "message": inputText,
        "chat_id": chatId
    ]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    guard line.starts(with: "data:") else { continue }
                    print("📡 History stream line: \(line)")
                    let dataLine = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // Stop signal (optional)
                    if dataLine == "[DONE]" || dataLine == "<|eot_id|>" {
                        break
                    }
                    
                    if let jsonData = dataLine.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ModelMessage.self, from: jsonData) {
                        continuation.yield(decoded.content)
                    }
                    
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func streamChatResponseWithPersonality(userInput: String, chatId: String?, userId: String, personalityManager: PersonalityManager, urgencyMode: String = "normal") async throws -> AsyncThrowingStream<String, Error> {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/chat_with_personality_stream")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var requestBody: [String: Any] = [
        "user_id": userId,
        "message": userInput,
        "urgency_mode": urgencyMode
    ]
    
    if let chatId = chatId {
        requestBody["chat_id"] = chatId
    }
    
    // Add personality_id from active personality
    if let activePersonality = personalityManager.activePersonality {
        requestBody["personality_id"] = activePersonality.id
        print("🎭 Using personality: \(activePersonality.name) (ID: \(activePersonality.id)) with urgency: \(urgencyMode)")
    } else {
        print("⚠️ No active personality found, backend will use default with urgency: \(urgencyMode)")
    }
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        let jsonString = String(line.dropFirst(6)) // Remove "data: "
                        
                        if jsonString.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            if let content = json["content"] as? String {
                                continuation.yield(content)
                            } else if let error = json["error"] as? String {
                                continuation.finish(throwing: NSError(domain: "StreamingError", code: 1, userInfo: [NSLocalizedDescriptionKey: error]))
                                return
                            }
                        }
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func streamChatResponseWithMemory(userInput: String, chatId: String?, userId: String, urgencyMode: String = "normal") async throws -> AsyncThrowingStream<String, Error> {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/chat_history_stream")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var requestBody: [String: Any] = [
        "user_id": userId,
        "message": userInput,
        "urgency_mode": urgencyMode
    ]
    
    if let chatId = chatId {
        requestBody["chat_id"] = chatId
    }
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    guard line.starts(with: "data:") else { continue }
                    print("🧠 Memory stream line: \(line)")
                    let dataLine = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // Stop signal (optional)
                    if dataLine == "[DONE]" || dataLine == "<|eot_id|>" {
                        break
                    }
                    
                    if let jsonData = dataLine.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ModelMessage.self, from: jsonData) {
                        continuation.yield(decoded.content)
                    }
                    
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func streamChatWithScreenAnalysis(userInput: String, chatId: String?, userId: String, windowId: Int? = nil) async throws -> AsyncThrowingStream<String, Error> {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/chat_with_screen_stream")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var requestBody: [String: Any] = [
        "user_id": userId,
        "message": userInput
    ]
    
    if let chatId = chatId {
        requestBody["chat_id"] = chatId
    }
    
    if let windowId = windowId {
        requestBody["window_id"] = windowId
    }
    
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

    let (bytes, _) = try await URLSession.shared.bytes(for: request)

    return AsyncThrowingStream { continuation in
        Task {
            do {
                for try await line in bytes.lines {
                    guard line.starts(with: "data:") else { continue }
                    print("👁️ Screen-aware stream line: \(line)")
                    let dataLine = line.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // Stop signal (optional)
                    if dataLine == "[DONE]" || dataLine == "<|eot_id|>" {
                        break
                    }
                    
                    if let jsonData = dataLine.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ModelMessage.self, from: jsonData) {
                        continuation.yield(decoded.content)
                    }
                    
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

func waitForModelReady(retryInterval: TimeInterval = 1.0) async throws {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/status")!

    while true {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Updated to handle new status response format
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let ready = json["ready"] as? Bool, ready == true {
                print("✅ Model is ready.")
                if let currentModel = json["current_model"] as? [String: Any] {
                    let modelId = currentModel["model_id"] as? String ?? "unknown"
                    let engine = currentModel["engine"] as? String ?? "unknown"
                    print("✅ Current model: \(modelId) (\(engine))")
                }
                return
            }
            print("⏳ Model not ready, retrying...")

        } catch {
            print("❌ Server not reachable, retrying in \(retryInterval)s...")
            // Try to find working server if current one fails
            await serverConfig.findWorkingServer()
        }
        
        try await Task.sleep(nanoseconds: UInt64(retryInterval * 1_000_000_000))
    }
}

func stopGeneration() async {
    let baseURL = serverConfig.currentServerURL
    guard let url = URL(string: "\(baseURL)/stop") else { return }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    do {
        let (_, _) = try await URLSession.shared.data(for: request)
        print("🛑 Stop signal sent to backend.")
    } catch {
        print("❌ Failed to send stop signal: \(error)")
    }
}

// Image generation request structure
struct ImageGenerationRequest: Encodable {
    let prompt: String
    let model_id: String?
}

// Image generation response structure
struct ImageGenerationResponse: Decodable {
    let success: Bool
    let image_data: String?
    let format: String?
    let prompt: String?
    let model: String?
    let provider: String?
    let error: String?
}

func generateImage(prompt: String, modelId: String? = nil) async throws -> ImageGenerationResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/generate_image")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let imageRequest = ImageGenerationRequest(prompt: prompt, model_id: modelId)
    request.httpBody = try JSONEncoder().encode(imageRequest)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    // Check for HTTP errors
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "ImageGenerationError", code: httpResponse.statusCode, 
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    let result = try JSONDecoder().decode(ImageGenerationResponse.self, from: data)
    return result
}


// Failed download structures
struct FailedDownload: Codable, Identifiable {
    let id = UUID()
    let unique_id: String
    let model_id: String
    let status: String
    let error_message: String?
    let partial_files: [PartialFile]
    let total_partial_size: Int
    let updated_at: String
}

struct PartialFile: Codable {
    let name: String
    let size: Int
}

struct FailedDownloadsResponse: Codable {
    let failed_downloads: [FailedDownload]
    let total_failed: Int
    let total_partial_size: Int
}

struct CleanupResponse: Codable {
    let status: String
    let cleaned_files: [String]?
    let bytes_freed: Int?
    let message: String
    let error: String?
}

// Cleanup functions
func getFailedDownloads() async throws -> FailedDownloadsResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/downloads/failed_downloads")!
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "FailedDownloadsError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(FailedDownloadsResponse.self, from: data)
}

func cleanupFailedDownload(uniqueId: String) async throws -> CleanupResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/downloads/cleanup_failed_download?unique_id=\(uniqueId)")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "CleanupError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(CleanupResponse.self, from: data)
}

func cleanupAllFailedDownloads() async throws -> CleanupResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/downloads/cleanup_all_failed")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "CleanupError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(CleanupResponse.self, from: data)
}

// MARK: - App Update Structures
struct UpdateInfo: Codable {
    let update_available: Bool
    let current_version: String
    let latest_version: String?
    let release_notes: String?
    let published_at: String?
    let download_url: String?
    let download_size: Int?
    let asset_name: String?
    let error: String?
    // Industry-level automatic update fields
    let auto_install_available: Bool?
    let consent_required: Bool?
    let message: String?
    let download_path: String?
    let auto_installation_completed: Bool?
    let install_result: [String: String]? // Simplified for Swift compatibility
}

struct UpdateDownloadResponse: Codable {
    let success: Bool
    let download_path: String?
    let message: String?
    let error: String?
}

struct UpdateInstallResponse: Codable {
    let success: Bool
    let message: String?
    let backup_path: String?
    let restart_required: Bool?
    let error: String?
}

struct AppVersionResponse: Codable {
    let version: String
    let platform: String
    let architecture: String?
    let repo: String
}

// MARK: - Update Functions
func checkForUpdates() async throws -> UpdateInfo {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/check_updates")!
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateInfo.self, from: data)
}

func downloadUpdate(downloadUrl: String) async throws -> UpdateDownloadResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/download_update")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let requestBody = ["download_url": downloadUrl]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateDownloadResponse.self, from: data)
}

func installUpdate(updateFilePath: String) async throws -> UpdateInstallResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/install_update")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let requestBody = ["update_file_path": updateFilePath]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateInstallResponse.self, from: data)
}

// MARK: - Industry-Level Automatic Update Functions

func installUpdateAutomatic(updateFilePath: String) async throws -> UpdateInstallResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/install_update_auto")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let requestBody = ["update_file_path": updateFilePath]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateInstallResponse.self, from: data)
}

func downloadAndInstallAutomatic(downloadUrl: String, userConsent: Bool = true) async throws -> UpdateInstallResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/download_and_install_auto")!
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    
    let requestBody = [
        "download_url": downloadUrl,
        "user_consent": userConsent
    ] as [String : Any]
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
    
    let (data, response) = try await URLSession.shared.data(for: request)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateInstallResponse.self, from: data)
}

func checkAndInstallUpdatesAutomatic(autoInstall: Bool = false, userConsent: Bool = false) async throws -> UpdateInfo {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/check_and_install_updates?auto_install=\(autoInstall)&user_consent=\(userConsent)")!
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(UpdateInfo.self, from: data)
}

func getAppVersion() async throws -> AppVersionResponse {
    let baseURL = serverConfig.currentServerURL
    let url = URL(string: "\(baseURL)/app_version")!
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
        let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "UpdateError", code: httpResponse.statusCode,
                     userInfo: [NSLocalizedDescriptionKey: errorMessage])
    }
    
    return try JSONDecoder().decode(AppVersionResponse.self, from: data)
}

class AppState: ObservableObject {
    @Published var modelReady = false
    @Published var currentModel: String = "No model loaded"
    @Published var currentEngine: String = ""
    @Published var isImageModel: Bool = false
    @Published var failedDownloads: [FailedDownload] = []
    @Published var isLoadingFailedDownloads = false
    @Published var cleanupMessage: String = ""
    
    // Update-related properties
    @Published var updateInfo: UpdateInfo?
    @Published var isCheckingForUpdates = false
    @Published var isDownloadingUpdate = false
    @Published var isInstallingUpdate = false
    @Published var updateMessage: String = ""
    @Published var currentAppVersion: String = "Unknown"
    @Published var downloadedUpdatePath: String?
    @Published var autoUpdateEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoUpdateEnabled, forKey: "autoUpdateEnabled")
        }
    }
    @Published var downloadProgress: Double = 0.0
    @Published var downloadBytesReceived: Int = 0
    @Published var downloadTotalBytes: Int = 0
    @Published var canResumeDownload: Bool = false
    @Published var isPaused: Bool = false
    
    private let modelManager = ModelManager()
    
    init() {
        // Load auto-update preference from UserDefaults
        self.autoUpdateEnabled = UserDefaults.standard.bool(forKey: "autoUpdateEnabled")
    }
    
    func updateStatus() async {
        await modelManager.checkServerStatus()
        
        await MainActor.run {
            self.modelReady = modelManager.isModelReady
            if let current = modelManager.currentModel {
                self.currentModel = current.model_id
                self.currentEngine = current.engine.uppercased()
                
                // Check if current model is an image model
                self.isImageModel = self.checkIfImageModel(modelId: current.model_id)
            } else {
                self.currentModel = "No model loaded"
                self.currentEngine = ""
                self.isImageModel = false
            }
        }
    }
    
    func loadFailedDownloads() async {
        await MainActor.run {
            self.isLoadingFailedDownloads = true
            self.cleanupMessage = ""
        }
        
        do {
            let response = try await getFailedDownloads()
            await MainActor.run {
                self.failedDownloads = response.failed_downloads
                self.isLoadingFailedDownloads = false
            }
        } catch {
            await MainActor.run {
                self.cleanupMessage = "Failed to load failed downloads: \(error.localizedDescription)"
                self.isLoadingFailedDownloads = false
            }
        }
    }
    
    func cleanupSingleDownload(_ uniqueId: String) async {
        do {
            let response = try await cleanupFailedDownload(uniqueId: uniqueId)
            await MainActor.run {
                self.cleanupMessage = response.message
                // Remove cleaned download from list
                self.failedDownloads.removeAll { $0.unique_id == uniqueId }
            }
        } catch {
            await MainActor.run {
                self.cleanupMessage = "Cleanup failed: \(error.localizedDescription)"
            }
        }
    }
    
    func cleanupAllDownloads() async {
        do {
            let response = try await cleanupAllFailedDownloads()
            await MainActor.run {
                self.cleanupMessage = response.message
                self.failedDownloads.removeAll()
            }
        } catch {
            await MainActor.run {
                self.cleanupMessage = "Cleanup failed: \(error.localizedDescription)"
            }
        }
    }
    
    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Update Methods
    func loadAppVersion() async {
        do {
            let versionInfo = try await getAppVersion()
            await MainActor.run {
                self.currentAppVersion = versionInfo.version
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to get app version: \(error.localizedDescription)"
            }
        }
    }
    
    func checkForUpdatesAction() async {
        await MainActor.run {
            self.isCheckingForUpdates = true
            self.updateMessage = ""
        }
        
        do {
            let updates = try await checkForUpdates()
            await MainActor.run {
                self.updateInfo = updates
                self.isCheckingForUpdates = false
                
                if updates.update_available {
                    self.updateMessage = "Update available: v\(updates.latest_version ?? "unknown")"
                    
                    // Check if this update is already downloaded
                    if let downloadUrl = updates.download_url {
                        Task {
                            await self.checkCompletedDownload(downloadUrl: downloadUrl)
                        }
                    }
                } else {
                    self.updateMessage = "You're running the latest version"
                }
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to check for updates: \(error.localizedDescription)"
                self.isCheckingForUpdates = false
            }
        }
    }
    
    func downloadUpdateAction() async {
        guard let updateInfo = updateInfo,
              let downloadUrl = updateInfo.download_url else { return }
        
        await MainActor.run {
            self.isDownloadingUpdate = true
            self.updateMessage = "Downloading update..."
        }
        
        do {
            let response = try await downloadUpdate(downloadUrl: downloadUrl)
            await MainActor.run {
                if response.success, let downloadPath = response.download_path {
                    self.downloadedUpdatePath = downloadPath
                    self.updateMessage = "Update downloaded successfully"
                } else {
                    self.updateMessage = response.error ?? "Download failed"
                }
                self.isDownloadingUpdate = false
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Download failed: \(error.localizedDescription)"
                self.isDownloadingUpdate = false
            }
        }
    }
    
    func installUpdateAction() async {
        guard let updatePath = downloadedUpdatePath else { return }
        
        await MainActor.run {
            self.isInstallingUpdate = true
            self.updateMessage = "Installing update..."
        }
        
        do {
            let response = try await installUpdate(updateFilePath: updatePath)
            await MainActor.run {
                if response.success {
                    self.updateMessage = response.message ?? "Update installed successfully"
                    if response.restart_required == true {
                        self.updateMessage += " - Restart required"
                    }
                } else {
                    self.updateMessage = response.error ?? "Installation failed"
                }
                self.isInstallingUpdate = false
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Installation failed: \(error.localizedDescription)"
                self.isInstallingUpdate = false
            }
        }
    }
    
    // MARK: - Unified Update Action
    
    func unifiedUpdateAction() async {
        guard let updateInfo = updateInfo,
              let downloadUrl = updateInfo.download_url else { return }
        
        await MainActor.run {
            self.isDownloadingUpdate = true
            self.downloadProgress = 0.0
            self.downloadBytesReceived = 0
            self.downloadTotalBytes = updateInfo.download_size ?? 0
            self.isPaused = false
            self.canResumeDownload = false
            self.updateMessage = "Starting download..."
        }
        
        do {
            if autoUpdateEnabled {
                // Start automatic download and install process
                await startAutomaticDownloadAndInstall(downloadUrl: downloadUrl)
            } else {
                // Start manual download only
                await startManualDownload(downloadUrl: downloadUrl)
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Update failed: \(error.localizedDescription)"
                self.isDownloadingUpdate = false
                self.isInstallingUpdate = false
                self.downloadProgress = 0.0
            }
        }
    }
    
    private func startAutomaticDownloadAndInstall(downloadUrl: String) async {
        do {
            // Start the automatic download and install process
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/download_and_install_auto")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = [
                "download_url": downloadUrl,
                "user_consent": true
            ] as [String : Any]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Start the download process (don't wait for completion)
            Task {
                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        let result = try JSONDecoder().decode(UpdateInstallResponse.self, from: data)
                        await MainActor.run {
                            if result.success {
                                self.updateMessage = result.message ?? "Update completed automatically"
                                if result.restart_required == true {
                                    self.updateMessage += " - Please restart the app"
                                }
                                self.downloadedUpdatePath = nil
                                self.updateInfo = nil
                            } else {
                                self.updateMessage = result.error ?? "Automatic update failed"
                            }
                            self.isDownloadingUpdate = false
                            self.isInstallingUpdate = false
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.updateMessage = "Automatic update failed: \(error.localizedDescription)"
                        self.isDownloadingUpdate = false
                        self.isInstallingUpdate = false
                    }
                }
            }
            
            // Start progress monitoring
            await monitorDownloadProgress()
            
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to start automatic update: \(error.localizedDescription)"
                self.isDownloadingUpdate = false
            }
        }
    }
    
    private func startManualDownload(downloadUrl: String) async {
        do {
            // Start the manual download process
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/download_update")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["download_url": downloadUrl]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            // Start the download process (don't wait for completion)
            // Inside startManualDownload
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(UpdateDownloadResponse.self, from: data)

            await MainActor.run {
              if result.success, let path = result.download_path {
                self.downloadedUpdatePath = path
                self.updateMessage = "Update downloaded successfully. Click Install."
              } else {
                self.updateMessage = result.error ?? "Download failed"
              }
              self.isDownloadingUpdate = false
            }

            // Now that the file exists on disk, let the progress monitor catch up
            await monitorDownloadProgress()
            
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to start download: \(error.localizedDescription)"
                self.isDownloadingUpdate = false
            }
        }
    }
    
    @MainActor
    private func monitorDownloadProgress() async {
        // Monitor download progress every 250ms for smoother updates
        var consecutiveZeroProgress = 0
        
        while await MainActor.run(body: { self.isDownloadingUpdate && !self.isPaused }) {
            await loadDownloadProgress()
            
            let currentProgress = await MainActor.run { self.downloadProgress }
            
            // Track if we're not getting progress updates
            if currentProgress == 0.0 {
                consecutiveZeroProgress += 1
            } else {
                consecutiveZeroProgress = 0
            }
            
            // If we haven't seen progress for 10 seconds, show intermediate message
            if consecutiveZeroProgress > 40 { // 40 * 250ms = 10 seconds
                await MainActor.run {
                    self.updateMessage = "Download starting... Please wait"
                }
            }
            
            // Check if download is complete
            if currentProgress >= 1.0 {
                await MainActor.run {
                    self.updateMessage = "Download completed successfully"
                }
                break
            }
            
            // Wait before next update (faster polling for better UX)
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
        }
        
        // Final check after loop ends
        await loadDownloadProgress()
    }
    
    func pauseUpdateDownload() async {
        do {
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/pause_update_download")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.isPaused = true
                    self.canResumeDownload = true
                    self.updateMessage = "Download paused"
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    self.updateMessage = "Failed to pause download: \(errorMessage)"
                }
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to pause download: \(error.localizedDescription)"
            }
        }
    }
    
    func resumeUpdateDownload() async {
        do {
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/resume_update_download")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            await MainActor.run {
                self.isPaused = false
                self.canResumeDownload = false
                self.updateMessage = "Resuming download..."
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let result = try JSONDecoder().decode([String: String].self, from: data)
                await MainActor.run {
                    if result["success"] == "true" {
                        self.updateMessage = result["message"] ?? "Download resumed"
                        if let downloadPath = result["download_path"] {
                            self.downloadedUpdatePath = downloadPath
                            self.downloadProgress = 1.0
                        }
                    } else {
                        self.updateMessage = result["error"] ?? "Failed to resume download"
                        self.canResumeDownload = true
                    }
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    self.updateMessage = "Failed to resume download: \(errorMessage)"
                    self.canResumeDownload = true
                }
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to resume download: \(error.localizedDescription)"
                self.canResumeDownload = true
            }
        }
    }
    
    func cancelUpdateDownload() async {
        do {
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/cancel_update_download")!
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await MainActor.run {
                    self.isDownloadingUpdate = false
                    self.isInstallingUpdate = false
                    self.isPaused = false
                    self.canResumeDownload = false
                    self.downloadProgress = 0.0
                    self.downloadBytesReceived = 0
                    self.downloadTotalBytes = 0
                    self.downloadedUpdatePath = nil
                    self.updateMessage = "Download cancelled"
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                await MainActor.run {
                    self.updateMessage = "Failed to cancel download: \(errorMessage)"
                }
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to cancel download: \(error.localizedDescription)"
            }
        }
    }
    
    func checkCompletedDownload(downloadUrl: String) async {
        do {
            let baseURL = serverConfig.currentServerURL
            let encodedUrl = downloadUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? downloadUrl
            let url = URL(string: "\(baseURL)/check_completed_download?download_url=\(encodedUrl)")!
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                
                await MainActor.run {
                    if let completed = result?["completed"] as? Bool, completed {
                        if let downloadPath = result?["download_path"] as? String {
                            self.downloadedUpdatePath = downloadPath
                            self.downloadProgress = 1.0
                            self.isDownloadingUpdate = false
                            self.isPaused = false
                            self.canResumeDownload = false
                            self.updateMessage = "Update ready to install"
                        }
                    }
                }
            }
        } catch {
            // Silently ignore errors for this check
        }
    }

    @MainActor
    func loadDownloadProgress() async {
        do {
            let baseURL = serverConfig.currentServerURL
            let url = URL(string: "\(baseURL)/download_progress")!
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return
            }
            
            guard
                let progressData = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rawProgress = progressData["progress"] as? Double
            else {
                return
            }
            
            // 1) Update the raw numbers
            downloadProgress      = rawProgress / 100.0
            downloadBytesReceived = (progressData["downloaded"] as? Int) ?? downloadBytesReceived
            downloadTotalBytes    = (progressData["total_size"] as? Int) ?? downloadTotalBytes
            
            // 2) Pause / resume state
            isPaused              = (progressData["is_paused"] as? Bool) ?? isPaused
            canResumeDownload     = isPaused && !(progressData["is_active"] as? Bool ?? false)
            
            // 3) Active download flag (only if not paused)
            if !isPaused {
                isDownloadingUpdate = (progressData["is_active"] as? Bool) ?? isDownloadingUpdate
            }
            
            // 4) Completed?
            if (progressData["is_complete"] as? Bool) == true {
                downloadProgress      = 1.0
                isDownloadingUpdate   = false
                isPaused              = false
                canResumeDownload     = false
                // **Optionally** flip this so your view shows “Install”
                // downloadedUpdatePath = someLocalPathFromServer
                updateMessage         = "Download completed successfully"
                return
            }
            
            // 5) Update the user-facing message
            if isDownloadingUpdate {
                let pct = Int(downloadProgress * 100)
                updateMessage = "Downloading… \(pct)%"
            } else if isPaused {
                updateMessage = "Download paused"
            }
            
        } catch {
            // You could log or set an error message here
        }
    }

    // MARK: - Industry-Level Automatic Update Actions
    
    func installUpdateAutomaticAction() async {
        guard let updatePath = downloadedUpdatePath else { return }
        
        await MainActor.run {
            self.isInstallingUpdate = true
            self.updateMessage = "Installing update automatically with app replacement..."
        }
        
        do {
            let response = try await installUpdateAutomatic(updateFilePath: updatePath)
            await MainActor.run {
                if response.success {
                    self.updateMessage = response.message ?? "App updated automatically"
                    if response.restart_required == true {
                        self.updateMessage += " - Please restart the app"
                    }
                    // Clear downloaded path since installation is complete
                    self.downloadedUpdatePath = nil
                } else {
                    self.updateMessage = response.error ?? "Automatic installation failed"
                }
                self.isInstallingUpdate = false
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Automatic installation failed: \(error.localizedDescription)"
                self.isInstallingUpdate = false
            }
        }
    }
    
    func downloadAndInstallAutomaticAction(userConsent: Bool = false) async {
        guard let updateInfo = updateInfo,
              let downloadUrl = updateInfo.download_url else { return }
        
        await MainActor.run {
            self.isDownloadingUpdate = true
            self.isInstallingUpdate = true
            self.updateMessage = "Downloading and installing update automatically..."
        }
        
        do {
            let response = try await downloadAndInstallAutomatic(downloadUrl: downloadUrl, userConsent: userConsent)
            await MainActor.run {
                if response.success {
                    self.updateMessage = response.message ?? "Update completed automatically"
                    if response.restart_required == true {
                        self.updateMessage += " - Please restart the app"
                    }
                    // Clear update info since installation is complete
                    self.downloadedUpdatePath = nil
                    self.updateInfo = nil
                } else {
                    self.updateMessage = response.error ?? "Automatic update failed"
                }
                self.isDownloadingUpdate = false
                self.isInstallingUpdate = false
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Automatic update failed: \(error.localizedDescription)"
                self.isDownloadingUpdate = false
                self.isInstallingUpdate = false
            }
        }
    }
    
    func checkAndInstallAutomaticAction(userConsent: Bool = false) async {
        await MainActor.run {
            self.isCheckingForUpdates = true
            self.updateMessage = "Checking for updates and installing automatically..."
        }
        
        do {
            let updates = try await checkAndInstallUpdatesAutomatic(autoInstall: true, userConsent: userConsent)
            await MainActor.run {
                self.updateInfo = updates
                self.isCheckingForUpdates = false
                
                if let installResult = updates.install_result {
                    if installResult["success"] as? Bool == true {
                        self.updateMessage = "Update installed automatically - Restart required"
                        self.updateInfo = nil // Clear since update is complete
                    } else {
                        self.updateMessage = installResult["error"] as? String ?? "Automatic update failed"
                    }
                } else if updates.update_available {
                    if updates.consent_required == true {
                        self.updateMessage = "Update available - User consent required for automatic installation"
                    } else {
                        self.updateMessage = "Update available: v\(updates.latest_version ?? "unknown")"
                    }
                } else {
                    self.updateMessage = "You're running the latest version"
                }
            }
        } catch {
            await MainActor.run {
                self.updateMessage = "Failed to check and install updates: \(error.localizedDescription)"
                self.isCheckingForUpdates = false
            }
        }
    }
    
    private func checkIfImageModel(modelId: String) -> Bool {
        // Check for image model patterns in model ID
        let imageKeywords = ["flux", "stable-diffusion", "dalle", "midjourney", "imagen"]
        let lowerModelId = modelId.lowercased()
        
        return imageKeywords.contains { keyword in
            lowerModelId.contains(keyword)
        }
    }
}
