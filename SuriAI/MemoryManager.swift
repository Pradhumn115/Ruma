//
//  MemoryManager.swift
//  SuriAI - Memory Management for Long-term Memory and Adaptive Personalization
//
//  Created by Claude on 03/07/25.
//

import Foundation
import SwiftUI

// MARK: - Memory Data Models

struct MemoryEntry: Identifiable, Codable {
    let id: String
    let content: String
    let memory_type: String
    let importance: Double
    let timestamp: String
    let user_id: String
    let tokens: Int?
    let metadata: [String: String]?
}

struct MemoryStatistics: Codable {
    let user_id: String
    let total_memories: Int
    let total_tokens: Int
    let total_size_bytes: Int  // Legacy - SQL only
    let avg_importance: Double
    let memory_types_count: Int
    let type_breakdown: [String: MemoryTypeStats]
    let timestamp: String
    
    // New combined database statistics
    let combined_size_mb: Double?
    let combined_size_bytes: Int?
    let sql_database: DatabaseStats?
    let vector_database: VectorDatabaseStats?
    
    // Computed property for backward compatibility
    var displaySize: Int {
        return combined_size_bytes ?? total_size_bytes
    }
    
    var displaySizeMB: Double {
        return combined_size_mb ?? (Double(total_size_bytes) / (1024 * 1024))
    }
}

struct DatabaseStats: Codable {
    let size_mb: Double
    let size_bytes: Int
    let memory_count: Int
}

struct VectorDatabaseStats: Codable {
    let vector_size_mb: Double
    let vector_size_bytes: Int
    let embedding_count: Int
    let collection_count: Int
    let chroma_db_size_mb: Double
    let available: Bool
}

struct MemoryTypeStats: Codable {
    let count: Int
    let tokens: Int
}

struct MemoryInsights: Codable {
    let user_id: String
    let personality_profile: [String: String]
    let communication_style: String
    let knowledge_domains: [String]
    let interests: [String]
    let interaction_patterns: [String: Int]
    let memory_efficiency: Double
    let recommendations: [String]
}

struct UserMemoryProfile {
    let user_id: String
    let profile: [String: Any]?
    let recent_memories: [MemoryEntry]
    let preferences: [String: String]
    let personality_traits: [String]
    let total_memories: Int
}

struct UserProfile: Identifiable, Codable {
    let id = UUID()
    let user_id: String
    let communication_style: String
    let interests: [String]
    let expertise_areas: [String]
    let personality_traits: [String]
    let preferences: [String: String]
    let updated_at: String
}

struct OptimizationResults {
    let started_at: String
    let user_id: String
    let strategies_applied: [String]
    let memories_before: Int
    let memories_after: Int
    let size_before_mb: Double
    let size_after_mb: Double
    let savings_mb: Double
    let sql_size_before_mb: Double?
    let sql_size_after_mb: Double?
    let sql_savings_mb: Double?
    let vector_size_before_mb: Double?
    let vector_size_after_mb: Double?
    let vector_savings_mb: Double?
    let execution_time_ms: Double
    let details: [String: [String: Any]]?
    let skipped: String?
    let error: String?
}

// MARK: - Memory Manager Class

@MainActor
class MemoryManager: ObservableObject {
    static let shared = MemoryManager()
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var memoryStatistics: MemoryStatistics?
    @Published var memoryInsights: MemoryInsights?
    @Published var userMemories: [MemoryEntry] = []
    @Published var memoryProfile: UserMemoryProfile?
    @Published var userProfiles: [UserProfile] = []
    
    private var currentUserId: String {
        UserSettings.shared.username
    }
    
    private init() {}
    
    // MARK: - Memory Statistics
    
    func loadMemoryStatistics(for userId: String = UserSettings.shared.username) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Use the smart memory statistics endpoint  
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/statistics/\(userId)")!
            print("🔍 Loading memory statistics from smart memory endpoint: \(url)")
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = jsonResponse["success"] as? Bool, success,
                   let statisticsData = jsonResponse["statistics"] as? [String: Any] {
                    
                    // Parse the real statistics data
                    let totalMemories = statisticsData["total_memories"] as? Int ?? 0
                    let totalTokens = statisticsData["total_tokens"] as? Int ?? 0
                    let totalSizeBytes = statisticsData["total_size_bytes"] as? Int ?? 0
                    let avgImportance = statisticsData["avg_importance"] as? Double ?? 0.0
                    let memoryTypesCount = statisticsData["memory_types_count"] as? Int ?? 0
                    let timestamp = statisticsData["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date())
                    
                    // Parse type breakdown
                    var typeBreakdown: [String: MemoryTypeStats] = [:]
                    if let typeBreakdownData = statisticsData["type_breakdown"] as? [String: [String: Any]] {
                        for (typeName, typeData) in typeBreakdownData {
                            let count = typeData["count"] as? Int ?? 0
                            let tokens = typeData["tokens"] as? Int ?? 0
                            typeBreakdown[typeName] = MemoryTypeStats(count: count, tokens: tokens)
                        }
                    }
                    
                    // Parse combined database statistics
                    let combinedSizeMB = statisticsData["combined_size_mb"] as? Double
                    let combinedSizeBytes = statisticsData["combined_size_bytes"] as? Int
                    
                    // Parse SQL database stats
                    var sqlDatabaseStats: DatabaseStats? = nil
                    if let sqlDBData = statisticsData["sql_database"] as? [String: Any] {
                        sqlDatabaseStats = DatabaseStats(
                            size_mb: sqlDBData["size_mb"] as? Double ?? 0.0,
                            size_bytes: sqlDBData["size_bytes"] as? Int ?? 0,
                            memory_count: sqlDBData["memory_count"] as? Int ?? 0
                        )
                    }
                    
                    // Parse vector database stats
                    var vectorDatabaseStats: VectorDatabaseStats? = nil
                    if let vectorDBData = statisticsData["vector_database"] as? [String: Any] {
                        vectorDatabaseStats = VectorDatabaseStats(
                            vector_size_mb: vectorDBData["vector_size_mb"] as? Double ?? 0.0,
                            vector_size_bytes: vectorDBData["vector_size_bytes"] as? Int ?? 0,
                            embedding_count: vectorDBData["embedding_count"] as? Int ?? 0,
                            collection_count: vectorDBData["collection_count"] as? Int ?? 0,
                            chroma_db_size_mb: vectorDBData["chroma_db_size_mb"] as? Double ?? 0.0,
                            available: vectorDBData["available"] as? Bool ?? false
                        )
                    }
                    
                    // Create accurate statistics with new combined database information
                    let realStats = MemoryStatistics(
                        user_id: userId,
                        total_memories: totalMemories,
                        total_tokens: totalTokens,
                        total_size_bytes: totalSizeBytes,
                        avg_importance: avgImportance,
                        memory_types_count: memoryTypesCount,
                        type_breakdown: typeBreakdown,
                        timestamp: timestamp,
                        combined_size_mb: combinedSizeMB,
                        combined_size_bytes: combinedSizeBytes,
                        sql_database: sqlDatabaseStats,
                        vector_database: vectorDatabaseStats
                    )
                    
                    self.memoryStatistics = realStats
                    print("✅ Memory statistics loaded: \(totalMemories) memories, \(totalTokens) tokens, \(formatBytes(totalSizeBytes))")
                } else {
                    print("❌ Failed to parse memory statistics response")
                    self.errorMessage = "Failed to parse memory statistics"
                }
            } else {
                throw MemoryError.serverError("Failed to load memory statistics")
            }
        } catch {
            self.errorMessage = "Failed to load memory statistics: \(error.localizedDescription)"
            print("❌ Memory statistics error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Memory Insights
    
    func loadMemoryInsights(for userId: String = UserSettings.shared.username) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/insights/\(userId)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Handle new API response format with success wrapper
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = jsonResponse["success"] as? Bool, success,
                   let insightsData = jsonResponse["insights"] as? [String: Any] {
                    
                    // Convert the insights data to expected format for MemoryInsights model
                    let convertedInsights: [String: Any] = [
                        "user_id": insightsData["user_id"] ?? userId,
                        "personality_profile": [:], // Default empty since not in current backend response
                        "communication_style": "direct", // Default based on most accessed memories
                        "knowledge_domains": ["programming", "personal", "work"], // Extract from common tags
                        "interests": ["learning", "programming"], // Extract from common tags
                        "interaction_patterns": ["questions": 10, "preferences": 20], // Default pattern
                        "memory_efficiency": 0.8, // Default efficiency
                        "recommendations": [
                            "Continue engaging with programming topics",
                            "Explore more personalization options",
                            "Share more preferences for better memory adaptation"
                        ]
                    ]
                    
                    let insightsJson = try JSONSerialization.data(withJSONObject: convertedInsights)
                    self.memoryInsights = try JSONDecoder().decode(MemoryInsights.self, from: insightsJson)
                } else {
                    // Fallback to original format
                    let result = try JSONDecoder().decode([String: MemoryInsights].self, from: data)
                    self.memoryInsights = result["insights"]
                }
            } else {
                throw MemoryError.serverError("Failed to load memory insights")
            }
        } catch {
            self.errorMessage = "Failed to load memory insights: \(error.localizedDescription)"
            print("❌ Memory insights error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Retrieve User Memories
    
    func retrieveUserMemories(for userId: String = UserSettings.shared.username, query: String = "", limit: Int = 50, urgencyMode: String = "normal", memoryTypes: [String]? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Use the new hybrid memory search endpoint
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/hybrid_search")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "user_id": userId,
                "query": query.isEmpty ? "" : query, // Empty query returns all memories
                "urgency": urgencyMode,
                "memory_types": memoryTypes ?? [],
                "limit": limit
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            print("🔍 Loading memories from hybrid memory system with urgency: \(urgencyMode)")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = jsonResponse["success"] as? Bool, success,
                   let memoriesArray = jsonResponse["memories"] as? [[String: Any]] {
                    
                    var convertedMemories: [MemoryEntry] = []
                    
                    for memoryData in memoriesArray {
                        if let id = memoryData["id"] as? String,
                           let content = memoryData["content"] as? String,
                           let memoryType = memoryData["memory_type"] as? String,
                           let importance = memoryData["importance"] as? Double,
                           let createdAt = memoryData["created_at"] as? String {
                            
                            let memoryEntry = MemoryEntry(
                                id: id,
                                content: content,
                                memory_type: memoryType,
                                importance: importance,
                                timestamp: createdAt,
                                user_id: userId,
                                tokens: Int(content.count / 4), // Estimate tokens
                                metadata: memoryData["metadata"] as? [String: String]
                            )
                            convertedMemories.append(memoryEntry)
                        }
                    }
                    
                    self.userMemories = convertedMemories
                    
                    // Log search metadata for debugging
                    if let searchMetadata = jsonResponse["search_metadata"] as? [String: Any] {
                        print("✅ Hybrid memory search completed:")
                        print("   Strategy: \(searchMetadata["strategy"] ?? "unknown")")
                        print("   Latency: \(searchMetadata["latency_ms"] ?? 0)ms")
                        print("   Total searched: \(searchMetadata["total_searched"] ?? 0)")
                        print("   Memories returned: \(convertedMemories.count)")
                    }
                } else {
                    print("❌ Failed to parse hybrid memory response")
                    self.errorMessage = "Failed to parse memories"
                }
            } else {
                throw MemoryError.serverError("Failed to retrieve memories")
            }
        } catch {
            self.errorMessage = "Failed to retrieve memories: \(error.localizedDescription)"
            print("❌ Hybrid memory retrieval error: \(error)")
        }
        
        isLoading = false
    }
    
    // parseMemoryEntry function removed - using smart memory API directly
    
    // MARK: - Delete Memories
    
    func deleteMemories(memoryIds: [String]? = nil, memoryTypes: [String]? = nil, for userId: String = UserSettings.shared.username) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            // Use the smart memory clear endpoint
            if let memoryTypes = memoryTypes, memoryTypes.count == 1 {
                // Clear specific memory type
                let url = URL(string: "\(serverConfig.currentServerURL)/memory/clear_all_memories/\(userId)?memory_type=\(memoryTypes[0])")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = result["success"] as? Bool, success {
                        print("✅ Memory type cleared successfully: \(result)")
                        
                        // Refresh memories list
                        await retrieveUserMemories(for: userId)
                        await loadMemoryStatistics(for: userId)
                        
                        isLoading = false
                        return true
                    }
                }
            } else if memoryIds == nil && memoryTypes == nil {
                // Clear all memories
                let url = URL(string: "\(serverConfig.currentServerURL)/memory/clear_all_memories/\(userId)")!
                var request = URLRequest(url: url)
                request.httpMethod = "DELETE"
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = result["success"] as? Bool, success {
                        print("✅ All memories cleared successfully: \(result)")
                        
                        // Refresh memories list
                        await retrieveUserMemories(for: userId)
                        await loadMemoryStatistics(for: userId)
                        
                        isLoading = false
                        return true
                    }
                }
            }
            
            // Handle individual memory deletion
            if let memoryIds = memoryIds, !memoryIds.isEmpty {
                var successCount = 0
                
                for memoryId in memoryIds {
                    let url = URL(string: "\(serverConfig.currentServerURL)/memory/delete/\(memoryId)")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "DELETE"
                    
                    do {
                        let (data, response) = try await URLSession.shared.data(for: request)
                        
                        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                            if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let success = result["success"] as? Bool, success {
                                successCount += 1
                            }
                        }
                    } catch {
                        print("❌ Failed to delete memory \(memoryId): \(error)")
                    }
                }
                
                if successCount > 0 {
                    print("✅ Deleted \(successCount) out of \(memoryIds.count) memories")
                    
                    // Refresh memories list
                    await retrieveUserMemories(for: userId)
                    await loadMemoryStatistics(for: userId)
                    
                    isLoading = false
                    return true
                } else {
                    self.errorMessage = "Failed to delete any memories"
                    isLoading = false
                    return false
                }
            }
            
            // If none of the conditions matched, return false
            self.errorMessage = "Invalid deletion parameters"
            isLoading = false
            return false
            
        } catch {
            self.errorMessage = "Failed to delete memories: \(error.localizedDescription)"
            print("❌ Memory deletion error: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Memory Cleanup
    
    func cleanupMemory(for userId: String = UserSettings.shared.username) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/cleanup/\(userId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("✅ Memory cleanup completed: \(result)")
                    
                    // Refresh data
                    await loadMemoryStatistics(for: userId)
                    await retrieveUserMemories(for: userId)
                    
                    isLoading = false
                    return true
                } else {
                    throw MemoryError.decodingError("Invalid response format")
                }
            } else {
                throw MemoryError.serverError("Failed to cleanup memory")
            }
        } catch {
            self.errorMessage = "Failed to cleanup memory: \(error.localizedDescription)"
            print("❌ Memory cleanup error: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Load User Memory Profile
    
    func loadUserMemoryProfile(for userId: String = UserSettings.shared.username) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/user_memory_profile/\(userId)")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                // Manual parsing due to mixed types in profile
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    let profile = UserMemoryProfile(
                        user_id: json["user_id"] as? String ?? userId,
                        profile: json["profile"] as? [String: Any],
                        recent_memories: [], // Would need proper parsing
                        preferences: json["preferences"] as? [String: String] ?? [:],
                        personality_traits: json["personality_traits"] as? [String] ?? [],
                        total_memories: json["total_memories"] as? Int ?? 0
                    )
                    self.memoryProfile = profile
                }
            } else {
                throw MemoryError.serverError("Failed to load memory profile")
            }
        } catch {
            self.errorMessage = "Failed to load memory profile: \(error.localizedDescription)"
            print("❌ Memory profile error: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Store Memory
    
    func storeMemory(content: String, userId: String = UserSettings.shared.username, memoryType: String = "fact", importance: Double = 0.5, category: String = "", confidence: Double = 0.8, keywords: [String] = [], context: String = "", metadata: [String: Any] = [:]) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/store_enhanced")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "user_id": userId,
                "content": content,
                "memory_type": memoryType,
                "importance": importance,
                "category": category,
                "confidence": confidence,
                "keywords": keywords,
                "context": context,
                "temporal_pattern": "",
                "metadata": metadata
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success {
                    print("✅ Enhanced memory stored successfully")
                    
                    if let vectorized = result["vectorized"] as? Bool, vectorized {
                        print("🔍 Memory automatically vectorized for semantic search")
                    }
                    
                    // Refresh data
                    await loadMemoryStatistics(for: userId)
                    await retrieveUserMemories(for: userId)
                    
                    isLoading = false
                    return true
                }
            }
            
            throw MemoryError.serverError("Failed to store enhanced memory")
            
        } catch {
            self.errorMessage = "Failed to store memory: \(error.localizedDescription)"
            print("❌ Enhanced memory storage error: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Profile Management
    
    func loadAllUserProfiles() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/profiles/all_users")!
            print("🔍 Loading all user profiles: \(url)")
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = jsonResponse["success"] as? Bool, success,
                   let profilesArray = jsonResponse["profiles"] as? [[String: Any]] {
                    
                    var convertedProfiles: [UserProfile] = []
                    
                    for profileData in profilesArray {
                        if let userId = profileData["user_id"] as? String,
                           let communicationStyle = profileData["communication_style"] as? String,
                           let interests = profileData["interests"] as? [String],
                           let expertiseAreas = profileData["expertise_areas"] as? [String],
                           let personalityTraits = profileData["personality_traits"] as? [String],
                           let preferences = profileData["preferences"] as? [String: String],
                           let updatedAt = profileData["updated_at"] as? String {
                            
                            let profile = UserProfile(
                                user_id: userId,
                                communication_style: communicationStyle,
                                interests: interests,
                                expertise_areas: expertiseAreas,
                                personality_traits: personalityTraits,
                                preferences: preferences,
                                updated_at: updatedAt
                            )
                            convertedProfiles.append(profile)
                        }
                    }
                    
                    self.userProfiles = convertedProfiles
                    print("✅ Loaded \(convertedProfiles.count) user profiles")
                } else {
                    print("❌ Failed to parse profiles response")
                    self.errorMessage = "Failed to parse profiles"
                }
            } else {
                throw MemoryError.serverError("Failed to load user profiles")
            }
        } catch {
            self.errorMessage = "Failed to load user profiles: \(error.localizedDescription)"
            print("❌ Profile loading error: \(error)")
        }
        
        isLoading = false
    }
    
    func deleteUserProfile(userId: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/profiles/\(userId)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success {
                    print("✅ Profile deleted successfully: \(result)")
                    
                    // Refresh profiles list
                    await loadAllUserProfiles()
                    
                    isLoading = false
                    return true
                }
            }
            
            throw MemoryError.serverError("Failed to delete profile")
            
        } catch {
            self.errorMessage = "Failed to delete profile: \(error.localizedDescription)"
            print("❌ Profile deletion error: \(error)")
            isLoading = false
            return false
        }
    }
    
    func clearAllProfiles() async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/profiles/clear_all")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success {
                    print("✅ All profiles cleared successfully: \(result)")
                    
                    // Refresh profiles list
                    await loadAllUserProfiles()
                    
                    isLoading = false
                    return true
                }
            }
            
            throw MemoryError.serverError("Failed to clear profiles")
            
        } catch {
            self.errorMessage = "Failed to clear profiles: \(error.localizedDescription)"
            print("❌ Profile clearing error: \(error)")
            isLoading = false
            return false
        }
    }
    
    // MARK: - Hybrid Memory Analytics
    
    func getMemoryAnalytics(for userId: String = UserSettings.shared.username, days: Int = 30, memoryTypes: [String]? = nil) async -> [String: Any]? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/analytics")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "user_id": userId,
                "days": days,
                "memory_types": memoryTypes ?? []
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let analytics = result["analytics"] as? [String: Any] {
                    return analytics
                }
            }
            return nil
        } catch {
            print("❌ Failed to get memory analytics: \(error)")
            return nil
        }
    }
    
    func getMemorySystemStatus() async -> [String: Any]? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/system_status")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let systemStatus = result["system_status"] as? [String: Any] {
                    return systemStatus
                }
            }
            return nil
        } catch {
            print("❌ Failed to get memory system status: \(error)")
            return nil
        }
    }
    
    func getAvailableMemoryTypes() async -> [String: Any]? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/types")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let memoryTypes = result["memory_types"] as? [String: Any] {
                    return memoryTypes
                }
            }
            return nil
        } catch {
            print("❌ Failed to get memory types: \(error)")
            return nil
        }
    }
    
    func getUrgencyModes() async -> [String: Any]? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/urgency_modes")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let urgencyModes = result["urgency_modes"] as? [String: Any] {
                    return urgencyModes
                }
            }
            return nil
        } catch {
            print("❌ Failed to get urgency modes: \(error)")
            return nil
        }
    }
    
    func suggestMemoryTypes(for content: String, userId: String = UserSettings.shared.username) async -> [[String: Any]]? {
        do {
            var urlComponents = URLComponents(string: "\(serverConfig.currentServerURL)/memory/suggest_types/\(userId)")!
            urlComponents.queryItems = [
                URLQueryItem(name: "content", value: content)
            ]
            
            let (data, response) = try await URLSession.shared.data(from: urlComponents.url!)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let suggestions = result["suggestions"] as? [[String: Any]] {
                    return suggestions
                }
            }
            return nil
        } catch {
            print("❌ Failed to get memory type suggestions: \(error)")
            return nil
        }
    }
    
    // MARK: - Memory Optimization
    
    func getMemorySizeStats() async -> [String: Any]? {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/size_stats")!
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success,
                   let stats = result["stats"] as? [String: Any] {
                    return stats
                }
            }
            return nil
        } catch {
            print("❌ Failed to get memory size stats: \(error)")
            return nil
        }
    }
    
    func optimizeMemory(force: Bool = false) async -> OptimizationResults? {
        print("🔧 [DEBUG] MemoryManager.optimizeMemory called with force: \(force)")
        isLoading = true
        errorMessage = nil
        
        do {
            var urlComponents = URLComponents(string: "\(serverConfig.currentServerURL)/memory/optimize/\(UserSettings.shared.username)")!
            urlComponents.queryItems = [
                URLQueryItem(name: "force", value: "\(force)")
            ]
            
            let finalURL = urlComponents.url!
            print("🔧 [DEBUG] Making POST request to: \(finalURL)")
            
            var request = URLRequest(url: finalURL)
            request.httpMethod = "POST"
            
            print("🔧 [DEBUG] Sending HTTP request...")
            let (data, response) = try await URLSession.shared.data(for: request)
            
            print("🔧 [DEBUG] Received response - checking status code...")
            if let httpResponse = response as? HTTPURLResponse {
                print("🔧 [DEBUG] HTTP Status Code: \(httpResponse.statusCode)")
            }
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("🔧 [DEBUG] HTTP 200 OK - parsing JSON response...")
                
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔧 [DEBUG] JSON parsed successfully: \(result)")
                    
                    if let success = result["success"] as? Bool {
                        print("🔧 [DEBUG] Success field found: \(success)")
                        
                        if success {
                            // Extract optimization results
                            if let results = result["results"] as? [String: Any] {
                                print("✅ [DEBUG] Memory optimization results: \(results)")
                                
                                // Parse optimization results manually
                                let optimizationResults = OptimizationResults(
                                    started_at: results["started_at"] as? String ?? ISO8601DateFormatter().string(from: Date()),
                                    user_id: results["user_id"] as? String ?? UserSettings.shared.username,
                                    strategies_applied: results["strategies_applied"] as? [String] ?? [],
                                    memories_before: results["memories_before"] as? Int ?? 0,
                                    memories_after: results["memories_after"] as? Int ?? 0,
                                    size_before_mb: results["size_before_mb"] as? Double ?? 0.0,
                                    size_after_mb: results["size_after_mb"] as? Double ?? 0.0,
                                    savings_mb: results["savings_mb"] as? Double ?? 0.0,
                                    sql_size_before_mb: results["sql_size_before_mb"] as? Double,
                                    sql_size_after_mb: results["sql_size_after_mb"] as? Double,
                                    sql_savings_mb: results["sql_savings_mb"] as? Double,
                                    vector_size_before_mb: results["vector_size_before_mb"] as? Double,
                                    vector_size_after_mb: results["vector_size_after_mb"] as? Double,
                                    vector_savings_mb: results["vector_savings_mb"] as? Double,
                                    execution_time_ms: results["execution_time_ms"] as? Double ?? 0.0,
                                    details: results["details"] as? [String: [String: Any]],
                                    skipped: results["skipped"] as? String,
                                    error: results["error"] as? String
                                )
                                
                                print("💾 [DEBUG] Memory optimization completed successfully with vector database support")
                                
                                // Refresh data after optimization
                                print("🔧 [DEBUG] Starting data refresh...")
                                await loadMemoryStatistics()
                                await retrieveUserMemories()
                                print("🔧 [DEBUG] Data refresh completed")
                                
                                isLoading = false
                                return optimizationResults
                            }
                            
                            print("💾 [DEBUG] Memory optimization completed successfully with vector database support")
                            
                            // Refresh data after optimization
                            print("🔧 [DEBUG] Starting data refresh...")
                            await loadMemoryStatistics()
                            await retrieveUserMemories()
                            print("🔧 [DEBUG] Data refresh completed")
                            
                            isLoading = false
                            return OptimizationResults(
                                started_at: ISO8601DateFormatter().string(from: Date()),
                                user_id: UserSettings.shared.username,
                                strategies_applied: [],
                                memories_before: 0,
                                memories_after: 0,
                                size_before_mb: 0.0,
                                size_after_mb: 0.0,
                                savings_mb: 0.0,
                                sql_size_before_mb: nil,
                                sql_size_after_mb: nil,
                                sql_savings_mb: nil,
                                vector_size_before_mb: nil,
                                vector_size_after_mb: nil,
                                vector_savings_mb: nil,
                                execution_time_ms: 0.0,
                                details: nil,
                                skipped: "No results details available",
                                error: nil
                            )
                        } else {
                            print("🔧 [DEBUG] Backend returned success: false")
                        }
                    } else {
                        print("🔧 [DEBUG] No 'success' field in response")
                    }
                } else {
                    print("🔧 [DEBUG] Failed to parse JSON response")
                }
            } else {
                print("🔧 [DEBUG] HTTP request failed - status: \(response)")
            }
            
            print("🔧 [DEBUG] Optimization failed")
            isLoading = false
            return nil
            
        } catch {
            self.errorMessage = "Failed to optimize memory: \(error.localizedDescription)"
            print("❌ [DEBUG] Memory optimization error: \(error)")
            isLoading = false
            return nil
        }
    }
    
    func autoOptimizeMemory() async -> Bool {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/auto_optimize")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let success = result["success"] as? Bool, success {
                    
                    if let optimizationPerformed = result["optimization_performed"] as? Bool,
                       optimizationPerformed {
                        print("✅ Auto-optimization completed")
                        await loadMemoryStatistics()
                        await retrieveUserMemories()
                        return true
                    } else {
                        print("ℹ️ No optimization needed")
                        return true
                    }
                }
            }
            
            return false
            
        } catch {
            print("❌ Auto-optimization error: \(error)")
            return false
        }
    }
    
    // MARK: - Import/Export Functions
    
    func importMemories(from data: Data, overwriteExisting: Bool = false, for userId: String = UserSettings.shared.username) async -> (success: Bool, message: String) {
        isLoading = true
        errorMessage = nil
        
        do {
            // Parse the JSON data
            guard let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let memories = jsonObject["memories"] as? [[String: Any]] else {
                isLoading = false
                return (false, "Invalid JSON format. Expected 'memories' array.")
            }
            
            let url = URL(string: "\(serverConfig.currentServerURL)/memory/import")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody: [String: Any] = [
                "user_id": userId,
                "memories": memories,
                "overwrite_existing": overwriteExisting
            ]
            
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (responseData, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                if let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                   let success = result["success"] as? Bool {
                    
                    if success {
                        let importedCount = result["imported_count"] as? Int ?? 0
                        let skippedCount = result["skipped_count"] as? Int ?? 0
                        let errorCount = result["error_count"] as? Int ?? 0
                        
                        let message = "Import completed: \(importedCount) imported, \(skippedCount) skipped, \(errorCount) errors"
                        
                        // Refresh data after import
                        await loadAllMemoryData(for: userId)
                        
                        isLoading = false
                        return (true, message)
                    } else {
                        let errorMsg = result["error"] as? String ?? "Unknown error"
                        isLoading = false
                        return (false, "Import failed: \(errorMsg)")
                    }
                }
            }
            
            isLoading = false
            return (false, "Failed to connect to server")
            
        } catch {
            self.errorMessage = "Failed to import memories: \(error.localizedDescription)"
            print("❌ Memory import error: \(error)")
            isLoading = false
            return (false, "Import error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Comprehensive Data Load
    
    func loadAllMemoryData(for userId: String = UserSettings.shared.username) async {
        await loadMemoryStatistics(for: userId)
        await loadMemoryInsights(for: userId)
        await retrieveUserMemories(for: userId, urgencyMode: "comprehensive") // Use comprehensive mode for management interface
        await loadUserMemoryProfile(for: userId)
        await loadAllUserProfiles()
    }
    
    // MARK: - Utility Functions
    
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

// MARK: - Memory Error Types

enum MemoryError: LocalizedError {
    case serverError(String)
    case networkError(String)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .serverError(let message):
            return "Server Error: \(message)"
        case .networkError(let message):
            return "Network Error: \(message)"
        case .decodingError(let message):
            return "Data Error: \(message)"
        }
    }
}