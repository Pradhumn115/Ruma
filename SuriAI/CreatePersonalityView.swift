//
//  CreatePersonalityView.swift
//  SuriAI
//
//  Created by AI Assistant on 30/06/25.
//

import SwiftUI

struct CreatePersonalityView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var personalityManager: PersonalityManager
    
    // Form fields
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedTraits: Set<PersonalityTrait> = []
    @State private var communicationStyle: CommunicationStyle = .conversational
    @State private var selectedDomains: Set<ExpertiseDomain> = [.general]
    @State private var formalityLevel: Double = 0.5
    @State private var creativityLevel: Double = 0.5
    @State private var empathyLevel: Double = 0.5
    @State private var humorLevel: Double = 0.3
    @State private var customInstructions: String = ""
    @State private var selectedTheme: PersonalityTheme = PersonalityTheme.predefinedThemes[0]
    @State private var customEmoji: String = ""
    @State private var useCustomEmoji: Bool = false
    
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Create AI Assistant")
                            .font(.title.bold())
                        Text("Design your perfect AI companion")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top)
                    
                    // Basic Info Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Basic Information", icon: "person.fill")
                        
                        VStack(spacing: 12) {
                            FormField(title: "Name", text: $name, placeholder: "e.g., Alex, Sarah, Dr. Smith")
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.subheadline.bold())
                                TextField("What makes this assistant special?", text: $description, axis: .vertical)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .lineLimit(3...6)
                            }
                        }
                    }
                    
                    // Personality Traits Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Personality Traits", icon: "heart.fill")
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(PersonalityTrait.allCases, id: \.self) { trait in
                                TraitToggle(
                                    trait: trait,
                                    isSelected: selectedTraits.contains(trait)
                                ) {
                                    if selectedTraits.contains(trait) {
                                        selectedTraits.remove(trait)
                                    } else {
                                        selectedTraits.insert(trait)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Communication Style Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Communication Style", icon: "bubble.left.and.bubble.right.fill")
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(CommunicationStyle.allCases, id: \.self) { style in
                                StyleToggle(
                                    style: style,
                                    isSelected: communicationStyle == style
                                ) {
                                    communicationStyle = style
                                }
                            }
                        }
                    }
                    
                    // Expertise Domains Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Expertise Areas", icon: "brain.head.profile")
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(ExpertiseDomain.allCases, id: \.self) { domain in
                                DomainToggle(
                                    domain: domain,
                                    isSelected: selectedDomains.contains(domain)
                                ) {
                                    if selectedDomains.contains(domain) {
                                        selectedDomains.remove(domain)
                                    } else {
                                        selectedDomains.insert(domain)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Personality Levels Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Personality Levels", icon: "slider.horizontal.3")
                        
                        VStack(spacing: 16) {
                            LevelSlider(title: "Formality", value: $formalityLevel, range: 0...1)
                            LevelSlider(title: "Creativity", value: $creativityLevel, range: 0...1)
                            LevelSlider(title: "Empathy", value: $empathyLevel, range: 0...1)
                            LevelSlider(title: "Humor", value: $humorLevel, range: 0...1)
                        }
                    }
                    
                    // Theme Selection Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Appearance", icon: "paintbrush.fill")
                        
                        // Custom Emoji Option
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Use Custom Emoji", isOn: $useCustomEmoji)
                                .font(.subheadline.bold())
                            
                            if useCustomEmoji {
                                HStack {
                                    TextField("Enter emoji or symbol", text: $customEmoji)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(maxWidth: 150)
                                        .onChange(of: customEmoji) { _, newValue in
                                            // Limit to 2 characters (emoji can be 2 chars)
                                            if newValue.count > 2 {
                                                customEmoji = String(newValue.prefix(2))
                                            }
                                        }
                                    
                                    if !customEmoji.isEmpty {
                                        Text(customEmoji)
                                            .font(.title2)
                                            .frame(width: 40, height: 40)
                                            .background(Color.gray.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                        
                        if !useCustomEmoji {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(0..<PersonalityTheme.predefinedThemes.count, id: \.self) { index in
                                    let theme = PersonalityTheme.predefinedThemes[index]
                                    ThemeSelector(
                                        theme: theme,
                                        isSelected: selectedTheme.colorTheme == theme.colorTheme
                                    ) {
                                        selectedTheme = theme
                                    }
                                }
                            }
                        }
                    }
                    
                    // Custom Instructions Section
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(title: "Custom Instructions", icon: "text.quote")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Special instructions for this assistant")
                                .font(.subheadline.bold())
                            TextField("Optional: Any specific behaviors or preferences...", text: $customInstructions, axis: .vertical)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .lineLimit(2...4)
                        }
                    }
                    
                    // Create Button
                    Button {
                        createPersonality()
                    } label: {
                        HStack {
                            if isCreating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }
                            Text(isCreating ? "Creating..." : "Create Assistant")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(canCreate ? Color.blue : Color.gray)
                        )
                    }
                    .disabled(!canCreate || isCreating)
                    .padding(.top)
                }
                .padding()
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !selectedTraits.isEmpty &&
        !selectedDomains.isEmpty
    }
    
    private func createPersonality() {
        isCreating = true
        
        let request = CreatePersonalityRequest(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            personalityTraits: Array(selectedTraits).map { $0.rawValue },
            communicationStyle: communicationStyle.rawValue,
            expertiseDomains: Array(selectedDomains).map { $0.rawValue },
            formalityLevel: formalityLevel,
            creativityLevel: creativityLevel,
            empathyLevel: empathyLevel,
            humorLevel: humorLevel,
            customInstructions: customInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarIcon: useCustomEmoji && !customEmoji.isEmpty ? customEmoji : selectedTheme.avatarIcon,
            colorTheme: selectedTheme.colorTheme
        )
        
        Task {
            let success = await personalityManager.createPersonality(request)
            await MainActor.run {
                isCreating = false
                if success {
                    dismiss()
                } else {
                    errorMessage = personalityManager.errorMessage ?? "Failed to create personality"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(title)
                .font(.headline.bold())
            Spacer()
        }
    }
}

struct FormField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.bold())
            TextField(placeholder, text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct TraitToggle: View {
    let trait: PersonalityTrait
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(trait.displayName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct StyleToggle: View {
    let style: CommunicationStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(style.displayName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct DomainToggle: View {
    let domain: ExpertiseDomain
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(domain.displayName)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct LevelSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
                .accentColor(.blue)
        }
    }
}

struct ThemeSelector: View {
    let theme: PersonalityTheme
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Text(theme.avatarIcon)
                    .font(.title2)
                Text(theme.colorTheme.capitalized)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(width: 60, height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreatePersonalityView(personalityManager: PersonalityManager())
}