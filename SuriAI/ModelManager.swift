import Foundation
import SwiftUI

// MARK: - Model Management Structures
struct ModelSwitchRequest: Codable {
    let model_id: String
    let model_type: String?
    let model_source: String?
}

struct ModelPreferenceRequest: Codable {
    let preference: String
}

struct ModelSwitchResponse: Codable {
    let status: String
    let message: String
    let model_info: CurrentModelInfo?
    let download_status: String?
}

struct CurrentModelInfo: Codable {
    let model_id: String
    let model_type: String
    let model_source: String?
    let engine: String
    let loaded: Bool
    let preference: String?
}

struct ServerStatus: Codable {
    let ready: Bool
    let current_model: CurrentModelInfo?
}

struct ModelCheckRequest: Codable {
    let model_id: String
}

struct ModelAvailability: Codable {
    let available: Bool
    let model_type: String
    let model_path: String?
    let reason: String?
}

struct AvailableModel: Codable, Identifiable {
    let id = UUID()
    let model_id: String
    let model_type: String
    let available: Bool
    let path: String
}

struct AvailableModelsResponse: Codable {
    let models: [AvailableModel]
    let total: Int
    let current_model: CurrentModelInfo?
}

// MARK: - Model Manager Class
class ModelManager: ObservableObject {
    @Published var currentModel: CurrentModelInfo?
    @Published var isModelReady: Bool = false
    @Published var availableModels: [AvailableModel] = []
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var isSwitchingModel: Bool = false
    
    private var baseURL: String {
        return serverConfig.currentServerURL
    }
    
    // MARK: - Status Check
    func checkServerStatus() async {
        guard let url = URL(string: "\(baseURL)/status") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let status = try JSONDecoder().decode(ServerStatus.self, from: data)
            
            await MainActor.run {
                self.isModelReady = status.ready
                self.currentModel = status.current_model
            }
        } catch {
            await MainActor.run {
                self.isModelReady = false
                self.currentModel = nil
                self.errorMessage = "Failed to connect to server: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Model Switching
    func switchModel(modelId: String, modelType: String? = nil, modelSource: String? = nil) async -> Bool {
        await MainActor.run {
            self.isSwitchingModel = true
            self.errorMessage = ""
        }
        
        guard let url = URL(string: "\(baseURL)/switch_model") else {
            await MainActor.run {
                self.errorMessage = "Invalid URL"
                self.isSwitchingModel = false
            }
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ModelSwitchRequest(model_id: modelId, model_type: modelType, model_source: modelSource)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    let switchResponse = try JSONDecoder().decode(ModelSwitchResponse.self, from: data)
                    
                    await MainActor.run {
                        if switchResponse.status == "success" {
                            self.currentModel = switchResponse.model_info
                            self.isModelReady = true
                            self.errorMessage = ""
                        } else if switchResponse.status == "download_required" {
                            self.errorMessage = switchResponse.message
                        } else {
                            self.errorMessage = switchResponse.message
                        }
                        self.isSwitchingModel = false
                    }
                    return switchResponse.status == "success"
                } else {
                    // Handle HTTP error
                    let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let errorDetail = errorData?["detail"] as? String ?? "Unknown error"
                    
                    await MainActor.run {
                        self.errorMessage = "Failed to switch model: \(errorDetail)"
                        self.isSwitchingModel = false
                    }
                    return false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Network error: \(error.localizedDescription)"
                self.isSwitchingModel = false
            }
        }
        
        return false
    }
    
    // MARK: - Check Model Availability
    func checkModelAvailability(modelId: String) async -> ModelAvailability? {
        guard let url = URL(string: "\(baseURL)/check_model") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ModelCheckRequest(model_id: modelId)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(ModelAvailability.self, from: data)
        } catch {
            print("Failed to check model availability: \(error)")
            return nil
        }
    }
    
    // MARK: - List Available Models
    func fetchAvailableModels() async {
        await MainActor.run {
            self.isLoading = true
        }
        
        guard let url = URL(string: "\(baseURL)/models") else {
            await MainActor.run {
                self.isLoading = false
            }
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AvailableModelsResponse.self, from: data)
            
            await MainActor.run {
                self.availableModels = response.models
                self.currentModel = response.current_model
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to fetch models: \(error.localizedDescription)"
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Utility Functions
    func clearError() {
        errorMessage = ""
    }
    
    func getCurrentModelDisplayName() -> String {
        guard let current = currentModel else { return "No model loaded" }
        return "\(current.model_id) (\(current.engine.uppercased()))"
    }
    
    func isCurrentModel(_ modelId: String) -> Bool {
        return currentModel?.model_id == modelId
    }
    
    // MARK: - Model Preference
    func setModelPreference(_ preference: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/set_model_preference") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody = ModelPreferenceRequest(preference: preference)
        
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                return true
            }
        } catch {
            print("Error setting model preference: \(error)")
        }
        
        return false
    }
}