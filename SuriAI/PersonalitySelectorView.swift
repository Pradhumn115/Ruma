//
//  PersonalitySelectorView.swift
//  SuriAI
//
//  Created by AI Assistant on 30/06/25.
//

import SwiftUI

struct PersonalitySelectorView: View {
    @ObservedObject var personalityManager: PersonalityManager
    @Environment(\.dismiss) private var dismiss
    @State private var showCreatePersonality = false
    @State private var showDeleteConfirmation = false
    @State private var personalityToDelete: AIPersonality?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView
                
                Divider()
                
                // Personalities List
                if personalityManager.isLoading {
                    loadingView
                } else if personalityManager.personalities.isEmpty {
                    emptyStateView
                } else {
                    personalitiesList
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCreatePersonality = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePersonality) {
            CreatePersonalityView(personalityManager: personalityManager)
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
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Personalities")
                        .font(.title.bold())
                    Text("Choose your AI assistant")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            
            // Current Active Personality Display
            if let active = personalityManager.activePersonality {
                HStack(spacing: 12) {
                    Text(active.avatarIcon)
                        .font(.title2)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Currently Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(active.name)
                            .font(.headline.bold())
                    }
                    
                    Spacer()
                    
                    Text("Active")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                )
            }
        }
        .padding()
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
            Text("Loading personalities...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No AI Personalities")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                
                Text("Create your first AI assistant to get started")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                showCreatePersonality = true
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("Create Personality")
                }
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    PersonalityCard(
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
    }
    
    private func selectPersonality(_ personality: AIPersonality) {
        guard !personality.isActive else { return }
        
        Task {
            let success = await personalityManager.switchPersonality(to: personality.id)
            if success {
                await MainActor.run {
                    // Optionally show success feedback
                    print("✅ Switched to \(personality.name)")
                }
            }
        }
    }
    
    private func deletePersonality(_ personality: AIPersonality) {
        Task {
            let success = await personalityManager.deletePersonality(personality.id)
            if !success {
                // Handle error if needed
                print("❌ Failed to delete personality")
            }
        }
    }
}

struct PersonalityCard: View {
    let personality: AIPersonality
    let isActive: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var showDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main card content
            HStack(spacing: 16) {
                // Avatar
                Text(personality.avatarIcon)
                    .font(.largeTitle)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(colorForTheme(personality.colorTheme).opacity(0.2))
                    )
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(personality.name)
                            .font(.headline.bold())
                        
                        if isActive {
                            Text("Active")
                                .font(.caption)
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
                        .lineLimit(showDetails ? nil : 2)
                    
                    // Traits preview
                    if !personality.personalityTraits.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(personality.personalityTraits.prefix(showDetails ? personality.personalityTraits.count : 3), id: \.self) { trait in
                                    Text(trait.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(colorForTheme(personality.colorTheme).opacity(0.2))
                                        .foregroundColor(colorForTheme(personality.colorTheme))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                
                                if !showDetails && personality.personalityTraits.count > 3 {
                                    Text("+\(personality.personalityTraits.count - 3)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Stats row
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.caption)
                            Text(personality.communicationStyle.capitalized)
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        
                        HStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                                .font(.caption)
                            Text("\(personality.usageCount) uses")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showDetails.toggle()
                            }
                        } label: {
                            Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
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
                    
                    // Only show delete for non-active personalities
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
            
            // Expanded details
            if showDetails {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                    
                    if !personality.expertiseDomains.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Expertise Areas")
                                .font(.subheadline.bold())
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(personality.expertiseDomains, id: \.self) { domain in
                                    Text(domain.capitalized)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.2))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Text("Created:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatDate(personality.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isActive ? colorForTheme(personality.colorTheme).opacity(0.5) : Color.black.opacity(0.1), lineWidth: isActive ? 2 : 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: showDetails)
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
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

#Preview {
    PersonalitySelectorView(personalityManager: PersonalityManager())
}