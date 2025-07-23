//
//  PersonalityModels.swift
//  SuriAI
//
//  Created by AI Assistant on 30/06/25.
//

import Foundation

// MARK: - AI Personality Data Models

struct AIPersonality: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let personalityTraits: [String]
    let communicationStyle: String
    let expertiseDomains: [String]
    let avatarIcon: String
    let colorTheme: String
    let isActive: Bool
    let usageCount: Int
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name, description
        case personalityTraits = "personality_traits"
        case communicationStyle = "communication_style"
        case expertiseDomains = "expertise_domains"
        case avatarIcon = "avatar_icon"
        case colorTheme = "color_theme"
        case isActive = "is_active"
        case usageCount = "usage_count"
        case createdAt = "created_at"
    }
}

struct CreatePersonalityRequest: Codable {
    let name: String
    let description: String
    let personalityTraits: [String]
    let communicationStyle: String
    let expertiseDomains: [String]
    let formalityLevel: Double
    let creativityLevel: Double
    let empathyLevel: Double
    let humorLevel: Double
    let customInstructions: String
    let avatarIcon: String
    let colorTheme: String
    
    enum CodingKeys: String, CodingKey {
        case name, description
        case personalityTraits = "personality_traits"
        case communicationStyle = "communication_style"
        case expertiseDomains = "expertise_domains"
        case formalityLevel = "formality_level"
        case creativityLevel = "creativity_level"
        case empathyLevel = "empathy_level"
        case humorLevel = "humor_level"
        case customInstructions = "custom_instructions"
        case avatarIcon = "avatar_icon"
        case colorTheme = "color_theme"
    }
}

struct SwitchPersonalityRequest: Codable {
    let personalityId: String
    
    enum CodingKeys: String, CodingKey {
        case personalityId = "personality_id"
    }
}

struct PersonalityStats: Codable {
    let totalPersonalities: Int
    let totalUsage: Int
    let averageUsage: Double
    let mostUsedPersonality: MostUsedPersonality
    
    enum CodingKeys: String, CodingKey {
        case totalPersonalities = "total_personalities"
        case totalUsage = "total_usage"
        case averageUsage = "average_usage"
        case mostUsedPersonality = "most_used_personality"
    }
    
    struct MostUsedPersonality: Codable {
        let name: String?
        let usageCount: Int
        
        enum CodingKeys: String, CodingKey {
            case name
            case usageCount = "usage_count"
        }
    }
}

// MARK: - API Response Models

struct PersonalityResponse: Codable {
    let success: Bool
    let personality: AIPersonality?
    let message: String?
}

struct PersonalitiesResponse: Codable {
    let success: Bool
    let personalities: [AIPersonality]
}

struct PersonalityStatsResponse: Codable {
    let success: Bool
    let stats: PersonalityStats
}

struct SwitchPersonalityResponse: Codable {
    let success: Bool
    let message: String
}

// MARK: - Predefined Options

enum PersonalityTrait: String, CaseIterable {
    case friendly = "friendly"
    case professional = "professional"
    case creative = "creative"
    case analytical = "analytical"
    case supportive = "supportive"
    case humorous = "humorous"
    case direct = "direct"
    case empathetic = "empathetic"
    case energetic = "energetic"
    case calm = "calm"
    
    var displayName: String {
        switch self {
        case .friendly: return "Friendly"
        case .professional: return "Professional"
        case .creative: return "Creative"
        case .analytical: return "Analytical"
        case .supportive: return "Supportive"
        case .humorous: return "Humorous"
        case .direct: return "Direct"
        case .empathetic: return "Empathetic"
        case .energetic: return "Energetic"
        case .calm: return "Calm"
        }
    }
}

enum CommunicationStyle: String, CaseIterable {
    case casual = "casual"
    case formal = "formal"
    case technical = "technical"
    case conversational = "conversational"
    case concise = "concise"
    case detailed = "detailed"
    
    var displayName: String {
        switch self {
        case .casual: return "Casual"
        case .formal: return "Formal"
        case .technical: return "Technical"
        case .conversational: return "Conversational"
        case .concise: return "Concise"
        case .detailed: return "Detailed"
        }
    }
}

enum ExpertiseDomain: String, CaseIterable {
    case general = "general"
    case technology = "technology"
    case business = "business"
    case creative = "creative"
    case science = "science"
    case education = "education"
    case health = "health"
    case entertainment = "entertainment"
    
    var displayName: String {
        switch self {
        case .general: return "General"
        case .technology: return "Technology"
        case .business: return "Business"
        case .creative: return "Creative"
        case .science: return "Science"
        case .education: return "Education"
        case .health: return "Health"
        case .entertainment: return "Entertainment"
        }
    }
}

struct PersonalityTheme {
    let colorTheme: String
    let avatarIcon: String
    let displayColor: String
    
    static let predefinedThemes = [
        PersonalityTheme(colorTheme: "blue", avatarIcon: "🤖", displayColor: "blue"),
        PersonalityTheme(colorTheme: "purple", avatarIcon: "🎨", displayColor: "purple"),
        PersonalityTheme(colorTheme: "green", avatarIcon: "👨‍🏫", displayColor: "green"),
        PersonalityTheme(colorTheme: "orange", avatarIcon: "🌟", displayColor: "orange"),
        PersonalityTheme(colorTheme: "red", avatarIcon: "🔥", displayColor: "red"),
        PersonalityTheme(colorTheme: "pink", avatarIcon: "💖", displayColor: "pink"),
        PersonalityTheme(colorTheme: "cyan", avatarIcon: "🧠", displayColor: "cyan"),
        PersonalityTheme(colorTheme: "yellow", avatarIcon: "☀️", displayColor: "yellow")
    ]
}