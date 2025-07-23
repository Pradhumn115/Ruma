//
//  PersonalityManager.swift
//  SuriAI
//
//  Created by AI Assistant on 30/06/25.
//

import Foundation

class PersonalityManager: ObservableObject {
    @Published var personalities: [AIPersonality] = []
    @Published var activePersonality: AIPersonality?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let userId = "pradhumn" // For now, using hardcoded user ID
    
    // MARK: - API Functions
    
    func loadPersonalities() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/personalities/\(userId)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PersonalitiesResponse.self, from: data)
            
            await MainActor.run {
                if response.success {
                    self.personalities = response.personalities
                    self.activePersonality = response.personalities.first { $0.isActive }
                    print("✅ Loaded \(response.personalities.count) personalities")
                } else {
                    self.errorMessage = "Failed to load personalities"
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Error loading personalities: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Failed to load personalities: \(error)")
        }
    }
    
    func createPersonality(_ request: CreatePersonalityRequest) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/personalities")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
            
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let response = try JSONDecoder().decode(PersonalityResponse.self, from: data)
            
            await MainActor.run {
                if response.success {
                    print("✅ Created personality successfully")
                    // Reload personalities to get the updated list
                    Task { await self.loadPersonalities() }
                } else {
                    self.errorMessage = response.message ?? "Failed to create personality"
                }
                self.isLoading = false
            }
            
            return response.success
        } catch {
            await MainActor.run {
                self.errorMessage = "Error creating personality: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Failed to create personality: \(error)")
            return false
        }
    }
    
    func switchPersonality(to personalityId: String) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/personalities/\(userId)/switch")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let request = SwitchPersonalityRequest(personalityId: personalityId)
            let encoder = JSONEncoder()
            urlRequest.httpBody = try encoder.encode(request)
            
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let response = try JSONDecoder().decode(SwitchPersonalityResponse.self, from: data)
            
            await MainActor.run {
                if response.success {
                    // Update local active personality
                    for i in 0..<self.personalities.count {
                        self.personalities[i] = AIPersonality(
                            id: self.personalities[i].id,
                            name: self.personalities[i].name,
                            description: self.personalities[i].description,
                            personalityTraits: self.personalities[i].personalityTraits,
                            communicationStyle: self.personalities[i].communicationStyle,
                            expertiseDomains: self.personalities[i].expertiseDomains,
                            avatarIcon: self.personalities[i].avatarIcon,
                            colorTheme: self.personalities[i].colorTheme,
                            isActive: self.personalities[i].id == personalityId,
                            usageCount: self.personalities[i].usageCount,
                            createdAt: self.personalities[i].createdAt
                        )
                    }
                    self.activePersonality = self.personalities.first { $0.id == personalityId }
                    print("✅ Switched to personality: \(self.activePersonality?.name ?? "Unknown")")
                } else {
                    self.errorMessage = response.message
                }
                self.isLoading = false
            }
            
            return response.success
        } catch {
            await MainActor.run {
                self.errorMessage = "Error switching personality: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Failed to switch personality: \(error)")
            return false
        }
    }
    
    func deletePersonality(_ personalityId: String) async -> Bool {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/personalities/\(userId)/\(personalityId)")!
            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "DELETE"
            
            let (data, _) = try await URLSession.shared.data(for: urlRequest)
            let response = try JSONDecoder().decode(SwitchPersonalityResponse.self, from: data)
            
            await MainActor.run {
                if response.success {
                    // Remove from local list
                    self.personalities.removeAll { $0.id == personalityId }
                    
                    // If this was the active personality, clear it
                    if self.activePersonality?.id == personalityId {
                        self.activePersonality = self.personalities.first { $0.isActive }
                    }
                    
                    print("✅ Deleted personality successfully")
                } else {
                    self.errorMessage = response.message
                }
                self.isLoading = false
            }
            
            return response.success
        } catch {
            await MainActor.run {
                self.errorMessage = "Error deleting personality: \(error.localizedDescription)"
                self.isLoading = false
            }
            print("❌ Failed to delete personality: \(error)")
            return false
        }
    }
    
    func getPersonalityStats() async -> PersonalityStats? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/personalities/\(userId)/stats")!
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PersonalityStatsResponse.self, from: data)
            
            if response.success {
                return response.stats
            }
        } catch {
            print("❌ Failed to load personality stats: \(error)")
        }
        return nil
    }
    
    // MARK: - Helper Functions
    
    func getActivePersonalityDisplayInfo() -> (icon: String, name: String, color: String) {
        guard let active = activePersonality else {
            return ("🤖", "Default AI", "blue")
        }
        return (active.avatarIcon, active.name, active.colorTheme)
    }
    
    func hasPersonalities() -> Bool {
        return !personalities.isEmpty
    }
}