import Foundation
import SwiftUI

class ServerConfig: ObservableObject {
    @Published var currentServerURL: String = "http://127.0.0.1:8000"
    @Published var isServerReachable: Bool = false
    @Published var availablePorts: [Int] = []
    
    private let defaultPorts = [8000, 8001, 8002, 8003, 8004, 8080, 3000, 5000]
    private let host = "127.0.0.1"
    
    init() {
        loadServerConfig()
        Task {
            await findWorkingServer()
        }
    }
    
    private func loadServerConfig() {
        if let data = UserDefaults.standard.data(forKey: "ServerConfig"),
           let config = try? JSONDecoder().decode(ServerConfigData.self, from: data) {
            currentServerURL = config.url
        }
    }
    
    private func saveServerConfig() {
        let config = ServerConfigData(url: currentServerURL)
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: "ServerConfig")
        }
    }
    
    @MainActor
    func findWorkingServer() async {
        print("🔍 Finding working server...")
        
        // Try current URL first
        if await checkServerHealth(currentServerURL) {
            isServerReachable = true
            print("✅ Current server is reachable: \(currentServerURL)")
            return
        }
        
        // Try default ports
        for port in defaultPorts {
            let url = "http://\(host):\(port)"
            if await checkServerHealth(url) {
                currentServerURL = url
                isServerReachable = true
                saveServerConfig()
                print("✅ Found working server: \(url)")
                return
            }
        }
        
        isServerReachable = false
        print("❌ No working server found")
    }
    
    private func checkServerHealth(_ url: String) async -> Bool {
        guard let serverURL = URL(string: "\(url)/status") else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: serverURL)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Server not reachable
        }
        return false
    }
    
    func getServerInfo() async -> ServerInfo? {
        guard let url = URL(string: "\(currentServerURL)/server_info") else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(ServerInfo.self, from: data)
        } catch {
            print("Error getting server info: \(error)")
            return nil
        }
    }
    
    func refreshServerConnection() {
        Task {
            await findWorkingServer()
        }
    }
    
    func setCustomServer(_ url: String) {
        currentServerURL = url
        saveServerConfig()
        Task {
            await MainActor.run {
                isServerReachable = false
            }
            if await checkServerHealth(url) {
                await MainActor.run {
                    isServerReachable = true
                }
            }
        }
    }
}

struct ServerConfigData: Codable {
    let url: String
}

struct ServerInfo: Codable {
    let host: String
    let port: Int?
    let url: String?
    let availablePorts: [Int]
    let defaultPorts: [Int]
    
    enum CodingKeys: String, CodingKey {
        case host, port, url
        case availablePorts = "available_ports"
        case defaultPorts = "default_ports"
    }
}

// Global instance
let serverConfig = ServerConfig()