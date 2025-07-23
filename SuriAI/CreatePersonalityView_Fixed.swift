//
//  CreatePersonalityView_Fixed.swift
//  SuriAI - Fixed responsive personality creation
//
//  Created by Claude on 01/07/25.
//

import SwiftUI

struct CreatePersonalityView_Fixed: View {
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
    @State private var useCustomEmoji: Bool = false
    @State private var customEmoji: String = ""
    
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var currentStep: Int = 0
    
    private let steps = ["Basic Info", "Personality", "Skills", "Appearance"]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Progress indicator
            progressView
            
            // Content area
            ScrollView {
                VStack(spacing: 20) {
                    switch currentStep {
                    case 0:
                        basicInfoStep
                    case 1:
                        personalityStep
                    case 2:
                        skillsStep
                    case 3:
                        appearanceStep
                    default:
                        basicInfoStep
                    }
                }
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Footer with navigation
            footerView
        }
        .frame(width: 700, height: 600) // Fixed size for better responsiveness
        .background(Material.ultraThick)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Create AI Assistant")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Step \(currentStep + 1) of \(steps.count): \(steps[currentStep])")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color.primary.opacity(0.02))
    }
    
    private var progressView: some View {
        HStack(spacing: 8) {
            ForEach(0..<steps.count, id: \.self) { index in
                Rectangle()
                    .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                    .frame(height: 3)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
        .padding(.horizontal)
    }
    
    private var basicInfoStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Basic Information")
                    .font(.title3.bold())
                Text("Give your AI assistant a name and description")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Assistant Name")
                        .font(.subheadline.bold())
                    TextField("e.g., Alex, Sarah, Dr. Smith", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline.bold())
                    TextField("What makes this assistant special?", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...5)
                        .font(.body)
                }
            }
            .frame(maxWidth: 400)
            
            Spacer()
        }
    }
    
    private var personalityStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Personality Traits")
                    .font(.title3.bold())
                Text("Choose traits that define your assistant's character")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PersonalityTrait.allCases, id: \.self) { trait in
                        TraitToggle_Fixed(
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
                .frame(maxWidth: 500)
                
                VStack(spacing: 16) {
                    Text("Communication Style")
                        .font(.subheadline.bold())
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(CommunicationStyle.allCases, id: \.self) { style in
                            StyleToggle_Fixed(
                                style: style,
                                isSelected: communicationStyle == style
                            ) {
                                communicationStyle = style
                            }
                        }
                    }
                    .frame(maxWidth: 400)
                }
            }
            
            Spacer()
        }
    }
    
    private var skillsStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Skills & Expertise")
                    .font(.title3.bold())
                Text("Define your assistant's knowledge areas and personality levels")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Text("Expertise Areas")
                        .font(.subheadline.bold())
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(ExpertiseDomain.allCases, id: \.self) { domain in
                            DomainToggle_Fixed(
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
                    .frame(maxWidth: 500)
                }
                
                VStack(spacing: 16) {
                    Text("Personality Levels")
                        .font(.subheadline.bold())
                    
                    VStack(spacing: 12) {
                        LevelSlider_Fixed(title: "Formality", value: $formalityLevel, icon: "person.fill.badge.minus")
                        LevelSlider_Fixed(title: "Creativity", value: $creativityLevel, icon: "paintbrush.fill")
                        LevelSlider_Fixed(title: "Empathy", value: $empathyLevel, icon: "heart.fill")
                        LevelSlider_Fixed(title: "Humor", value: $humorLevel, icon: "face.smiling.fill")
                    }
                    .frame(maxWidth: 400)
                }
            }
            
            Spacer()
        }
    }
    
    private var appearanceStep: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "paintbrush.pointed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                Text("Appearance & Instructions")
                    .font(.title3.bold())
                Text("Customize your assistant's appearance and add special instructions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 20) {
                // Custom Emoji Option
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Avatar & Theme")
                            .font(.subheadline.bold())
                        Spacer()
                        Toggle("Custom Emoji", isOn: $useCustomEmoji)
                            .toggleStyle(SwitchToggleStyle(tint: .blue))
                    }
                    
                    if useCustomEmoji {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "face.smiling")
                                    .foregroundStyle(.blue)
                                Text("Choose your custom emoji")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tap the text field below, then tap the 😀 button on your keyboard to access emojis!")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                Text("Or choose from popular options below:")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            
                            // Quick emoji suggestions
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Popular choices:")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                                    ForEach(["🤖", "🧠", "✨", "🦄", "👽", "🔥", "💎", "🌟"], id: \.self) { emoji in
                                        Button(action: {
                                            customEmoji = emoji
                                        }) {
                                            Text(emoji)
                                                .font(.system(size: 20))
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    Circle()
                                                        .fill(customEmoji == emoji ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("🎯 Tap here for emoji keyboard", text: $customEmoji)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(maxWidth: 250)
                                        .onChange(of: customEmoji) { _, newValue in
                                            // Limit to 2 characters (emoji can be 2 chars)
                                            if newValue.count > 2 {
                                                customEmoji = String(newValue.prefix(2))
                                            }
                                        }
                                    
                                    Text("💡 When emoji keyboard opens, long press emojis for variations!")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                
                                // Preview
                                if !customEmoji.isEmpty {
                                    VStack(spacing: 6) {
                                        Text(customEmoji)
                                            .font(.system(size: 40))
                                            .frame(width: 60, height: 60)
                                            .background(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 16))
                                            .shadow(color: .blue.opacity(0.2), radius: 4, x: 0, y: 2)
                                        
                                        Text("Your Avatar")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    VStack(spacing: 6) {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(Color.gray.opacity(0.1))
                                            .frame(width: 60, height: 60)
                                            .overlay(
                                                Image(systemName: "photo.badge.plus")
                                                    .foregroundStyle(.gray)
                                                    .font(.title2)
                                            )
                                        
                                        Text("Preview")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                        )
                    } else {
                        VStack(spacing: 16) {
                            Text("Choose Theme")
                                .font(.subheadline.bold())
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                                ForEach(0..<PersonalityTheme.predefinedThemes.count, id: \.self) { index in
                                    let theme = PersonalityTheme.predefinedThemes[index]
                                    ThemeSelector_Fixed(
                                        theme: theme,
                                        isSelected: selectedTheme.colorTheme == theme.colorTheme
                                    ) {
                                        selectedTheme = theme
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 400)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Instructions (Optional)")
                        .font(.subheadline.bold())
                    TextField("Any specific behaviors or preferences...", text: $customInstructions, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .font(.body)
                }
                .frame(maxWidth: 400)
            }
            
            Spacer()
        }
    }
    
    private var footerView: some View {
        HStack {
            // Back button
            Button {
                if currentStep > 0 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep -= 1
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.bordered)
            .disabled(currentStep == 0)
            
            Spacer()
            
            // Step indicator
            Text("\(currentStep + 1) of \(steps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Next/Create button
            Button {
                if currentStep < steps.count - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentStep += 1
                    }
                } else {
                    createPersonality()
                }
            } label: {
                HStack(spacing: 6) {
                    if isCreating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    }
                    
                    if currentStep < steps.count - 1 {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    } else {
                        Text(isCreating ? "Creating..." : "Create Assistant")
                    }
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(canProceed ? Color.blue : Color.gray)
                )
            }
            .buttonStyle(.plain)
            .disabled(!canProceed || isCreating)
        }
        .padding()
        .background(Color.primary.opacity(0.02))
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case 0:
            return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                   !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 1:
            return !selectedTraits.isEmpty
        case 2:
            return !selectedDomains.isEmpty
        case 3:
            return useCustomEmoji ? !customEmoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : true
        default:
            return false
        }
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
            avatarIcon: useCustomEmoji ? customEmoji : selectedTheme.avatarIcon,
            colorTheme: useCustomEmoji ? "blue" : selectedTheme.colorTheme
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

// MARK: - Fixed Supporting Views

struct TraitToggle_Fixed: View {
    let trait: PersonalityTrait
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(trait.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct StyleToggle_Fixed: View {
    let style: CommunicationStyle
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(style.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct DomainToggle_Fixed: View {
    let domain: ExpertiseDomain
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            Text(domain.displayName)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.blue : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
                .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct LevelSlider_Fixed: View {
    let title: String
    @Binding var value: Double
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.subheadline.bold())
                .frame(width: 80, alignment: .leading)
            
            Slider(value: $value, in: 0...1)
                .accentColor(.blue)
            
            Text("\(Int(value * 100))%")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
    }
}

struct ThemeSelector_Fixed: View {
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
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue.opacity(0.2) : Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CreatePersonalityView_Fixed(personalityManager: PersonalityManager())
}