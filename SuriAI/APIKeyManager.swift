import Foundation
import SwiftUI

// MARK: - API Key Management Structures
struct APIKeyRequest: Codable {
    let provider: String
    let api_key: String
    let name: String?
    let model: String?
}

struct APIKeyInfo: Codable, Identifiable {
    let id = UUID()
    let provider: String
    let name: String
    let masked_key: String
    let created_at: String
    let last_tested: String?
    let status: String
    let model: String?
    
    enum CodingKeys: String, CodingKey {
        case provider, name
        case masked_key = "masked_key"
        case created_at = "created_at"
        case last_tested = "last_tested"
        case status, model
    }
}

struct APIKeysResponse: Codable {
    let api_keys: [APIKeyInfo]
    let total: Int
}

struct APIKeyTestResult: Codable {
    let valid: Bool
    let message: String?
    let error: String?
    let models_count: Int?
}

struct SupportedProvider: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let website: String
    let default_models: [String]?
}

struct SupportedProvidersResponse: Codable {
    let providers: [SupportedProvider]
}

// MARK: - API Key Manager Class
class APIKeyManager: ObservableObject {
    @Published var apiKeys: [APIKeyInfo] = []
    @Published var supportedProviders: [SupportedProvider] = []
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var testResults: [String: APIKeyTestResult] = [:]
    @Published var availableModels: [String: [String]] = [:]
    
    private var baseURL: String {
        return serverConfig.currentServerURL
    }
    
    init() {
        print("APIKeyManager initialized")
        Task {
            // Wait for server config to initialize
            await serverConfig.findWorkingServer()
            print("APIKeyManager using baseURL: \(baseURL)")
            print("Loading supported providers...")
            await loadSupportedProviders()
            print("Loading API keys...")
            await loadAPIKeys()
        }
    }
    
    // MARK: - Load Data
    func loadSupportedProviders() async {
        guard let url = URL(string: "\(baseURL)/api_keys/supported_providers") else { 
            await MainActor.run {
                self.errorMessage = "Invalid URL for providers"
            }
            return 
        }
        
        do {
            print("Making request to: \(url)")
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 10.0
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("Received response with \(data.count) bytes")
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse {
                print("HTTP Status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    await MainActor.run {
                        self.errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    }
                    return
                }
            }
            
            // Debug: Print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Providers response: \(jsonString)")
            }
            
            let decodedResponse = try JSONDecoder().decode(SupportedProvidersResponse.self, from: data)
            print("Successfully decoded \(decodedResponse.providers.count) providers")
            
            await MainActor.run {
                self.supportedProviders = decodedResponse.providers
                self.errorMessage = "" // Clear any previous errors
                
                // Load default models for each provider
                for provider in decodedResponse.providers {
                    if let models = provider.default_models {
                        self.availableModels[provider.id] = models
                    }
                }
            }
        } catch let error as DecodingError {
            print("Decoding error: \(error)")
            await MainActor.run {
                self.errorMessage = "Data parsing error: \(error.localizedDescription)"
            }
        } catch let error as URLError {
            print("Network error: \(error)")
            await MainActor.run {
                self.errorMessage = "Network error: \(error.localizedDescription)"
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load providers: \(error.localizedDescription)"
            }
            print("Unknown error loading providers: \(error)")
        }
    }
    
    func loadAPIKeys() async {
        await MainActor.run {
            self.isLoading = true
        }
        
        guard let url = URL(string: "\(baseURL)/api_keys/api_keys") else {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Invalid URL for API keys"
            }
            return
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            // Check HTTP response
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                await MainActor.run {
                    self.errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    self.isLoading = false
                }
                return
            }
            
            // Debug: Print raw response
            if let jsonString = String(data: data, encoding: .utf8) {
                print("API Keys response: \(jsonString)")
            }
            
            let decodedResponse = try JSONDecoder().decode(APIKeysResponse.self, from: data)
            
            await MainActor.run {
                self.apiKeys = decodedResponse.api_keys
                self.isLoading = false
                self.errorMessage = "" // Clear any previous errors
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to load API keys: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("Error loading API keys: \(error)")
        }
    }
    
    // MARK: - Add API Key
    func addAPIKey(provider: String, apiKey: String, name: String? = nil, model: String? = nil) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api_keys/add_api_key") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let keyRequest = APIKeyRequest(provider: provider, api_key: apiKey, name: name, model: model)
        
        do {
            request.httpBody = try JSONEncoder().encode(keyRequest)
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await loadAPIKeys() // Refresh the list
                return true
            } else {
                if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let detail = errorData["detail"] as? String {
                    await MainActor.run {
                        self.errorMessage = detail
                    }
                }
                return false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to add API key: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // MARK: - Remove API Key
    func removeAPIKey(provider: String) async -> Bool {
        guard let url = URL(string: "\(baseURL)/api_keys/api_key/\(provider)") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                await loadAPIKeys() // Refresh the list
                return true
            }
            return false
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to remove API key: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    // MARK: - Test API Key
    func testAPIKey(provider: String) async {
        guard let url = URL(string: "\(baseURL)/api_keys/test_api_key/\(provider)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let result = try JSONDecoder().decode(APIKeyTestResult.self, from: data)
            
            await MainActor.run {
                self.testResults[provider] = result
            }
            
            // Refresh API keys to get updated status
            await loadAPIKeys()
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to test API key: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Utility Functions
    func getAPIKey(for provider: String) -> APIKeyInfo? {
        return apiKeys.first { $0.provider == provider }
    }
    
    func getProvider(for id: String) -> SupportedProvider? {
        return supportedProviders.first { $0.id == id }
    }
    
    func getModels(for providerId: String) -> [String] {
        return availableModels[providerId] ?? []
    }
    
    func clearError() {
        errorMessage = ""
    }
    
    func reload() async {
        await loadSupportedProviders()
        await loadAPIKeys()
    }
    
    func getStatusColor(for status: String) -> Color {
        switch status {
        case "active":
            return .green
        case "invalid":
            return .red
        case "untested":
            return .orange
        default:
            return .gray
        }
    }
    
    func getStatusIcon(for status: String) -> String {
        switch status {
        case "active":
            return "checkmark.circle.fill"
        case "invalid":
            return "xmark.circle.fill"
        case "untested":
            return "questionmark.circle.fill"
        default:
            return "circle"
        }
    }
}