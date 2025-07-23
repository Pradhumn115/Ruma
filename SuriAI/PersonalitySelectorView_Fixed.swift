//
//  PersonalitySelectorView_Fixed.swift
//  SuriAI - Fixed responsive personality selector
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct PersonalitySelectorView_Fixed: View {
    @ObservedObject var personalityManager: PersonalityManager
    @Environment(\.dismiss) private var dismiss
    @State private var showCreatePersonality = false
    @State private var showDeleteConfirmation = false
    @State private var personalityToDelete: AIPersonality?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with proper sizing
            headerView
            
            Divider()
            
            // Content area with proper sizing
            Group {
                if personalityManager.isLoading {
                    loadingView
                } else if personalityManager.personalities.isEmpty {
                    emptyStateView
                } else {
                    personalitiesList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Footer with action buttons
            footerView
        }
        .frame(width: 600, height: 500) // Fixed size for better responsiveness
        .background(Material.ultraThick)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .sheet(isPresented: $showCreatePersonality) {
            CreatePersonalityView_Fixed(personalityManager: personalityManager)
        }
        .alert("Delete Personality", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let personality = personalityToDelete {
                    deletePersonality(personality)
                }
            }
        } message: {
            if let personality = personalityToDelete {
                Text("Are you sure you want to delete '\(personality.name)'? This action cannot be undone.")
            }
        }
        .onAppear {
            Task {
                await personalityManager.loadPersonalities()
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 16) {
            // Title row
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Personalities")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                    Text("Choose your AI assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            // Current Active Personality Display
            if let active = personalityManager.activePersonality {
                ActivePersonalityCard(personality: active)
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)
            Text("Loading personalities...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No AI Personalities")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                
                Text("Create your first AI assistant to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showCreatePersonality = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("Create Your First Assistant")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var personalitiesList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(personalityManager.personalities) { personality in
                    CompactPersonalityCard(
                        personality: personality,
                        isActive: personality.isActive,
                        onSelect: {
                            selectPersonality(personality)
                        },
                        onDelete: {
                            personalityToDelete = personality
                            showDeleteConfirmation = true
                        }
                    )
                }
            }
            .padding()
        }
        .background(Color.clear)
    }
    
    private var footerView: some View {
        HStack {
            Text("\(personalityManager.personalities.count) personalities")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                showCreatePersonality = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("New Assistant")
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.primary.opacity(0.02))
    }
    
    private func selectPersonality(_ personality: AIPersonality) {
        guard !personality.isActive else { return }
        
        Task {
            let success = await personalityManager.switchPersonality(to: personality.id)
            if success {
                await MainActor.run {
                    print("✅ Switched to \(personality.name)")
                }
            }
        }
    }
    
    private func deletePersonality(_ personality: AIPersonality) {
        Task {
            let success = await personalityManager.deletePersonality(personality.id)
            if !success {
                print("❌ Failed to delete personality")
            }
        }
    }
}

// MARK: - Supporting Views

struct ActivePersonalityCard: View {
    let personality: AIPersonality
    
    var body: some View {
        HStack(spacing: 12) {
            Text(personality.avatarIcon)
                .font(.title2)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.green.opacity(0.2))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Currently Active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(personality.name)
                    .font(.headline.bold())
                    .foregroundStyle(.primary)
            }
            
            Spacer()
            
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 8, height: 8)
                Text("Active")
                    .font(.caption.bold())
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

struct CompactPersonalityCard: View {
    let personality: AIPersonality
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar
            Text(personality.avatarIcon)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(colorForTheme(personality.colorTheme).opacity(0.2))
                )
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(personality.name)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                    
                    if isActive {
                        Text("Active")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Spacer()
                }
                
                Text(personality.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                // Traits preview
                if !personality.personalityTraits.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(personality.personalityTraits.prefix(3), id: \.self) { trait in
                            Text(trait.capitalized)
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(colorForTheme(personality.colorTheme).opacity(0.15))
                                .foregroundColor(colorForTheme(personality.colorTheme))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        
                        if personality.personalityTraits.count > 3 {
                            Text("+\(personality.personalityTraits.count - 3)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
            
            // Action buttons
            VStack(spacing: 8) {
                Button {
                    onSelect()
                } label: {
                    Text(isActive ? "Active" : "Select")
                        .font(.caption.bold())
                        .foregroundColor(isActive ? .green : .white)
                        .frame(width: 60, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isActive ? Color.green.opacity(0.2) : Color.blue)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isActive)
                
                if !isActive {
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isActive ? colorForTheme(personality.colorTheme).opacity(0.4) : Color.primary.opacity(0.1), lineWidth: isActive ? 2 : 1)
                )
        )
    }
    
    private func colorForTheme(_ theme: String) -> Color {
        switch theme.lowercased() {
        case "blue": return .blue
        case "purple": return .purple
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "cyan": return .cyan
        case "yellow": return .yellow
        default: return .blue
        }
    }
}

#Preview {
    PersonalitySelectorView_Fixed(personalityManager: PersonalityManager())
}