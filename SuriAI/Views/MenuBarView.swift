//
//  MenuBarView.swift
//  Ruma - Simplified Menu Bar Interface
//
//  Created by Claude on 06/07/25.
//

import SwiftUI
import HotKey

struct MenuBarView: View {
    @ObservedObject var personalityManager: PersonalityManager
    @ObservedObject var dynamicPlacementManager: DynamicIslandPlacementManager
    @ObservedObject var screenCaptureManager: ScreenCaptureManager
    @ObservedObject var appState: AppState
    @ObservedObject var userSettings: UserSettings
    @Environment(\.openWindow) private var openWindow
    @State private var showEditMode = false
    
    let onCreateNewChat: () -> Void
    let onToggleChatHistory: () -> Void
    let onToggleDynamicMode: () -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            headerSection
            
            Divider()
            
            // User Info Display (Read-only)
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Settings")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                VStack(spacing: 6) {
                    HStack {
                        Text("Username:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text(userSettings.username)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    
                    HStack {
                        Text("Hotkey:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(userSettings.customHotkeyDisplay)
                            .font(.subheadline.monospaced().weight(.medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            
            // Edit Preferences Button
            Button {
                openWindow(id: "PreferencesWindow")
                
                    
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 24, height: 24)
                    
                    Text("Edit Preferences")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.borderless)
            
            Divider()
            
            // Action Buttons
            VStack(spacing: 8) {
                Button {
                    openWindow(id: "ModelHubWindow")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "cube.box.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 24, height: 24)
                        
                        Text("Open Model Hub")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.borderless)

                Button {
                    openWindow(id: "MemoryManagementWindow")
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.purple)
                            .frame(width: 24, height: 24)
                        
                        Text("Memory Management")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                    )
                }
                .buttonStyle(.borderless)
            }
            
            Divider()
            
            // Quit Button
            MenuButton(
                icon: "power",
                title: "Quit Ruma",
                color: .red,
                action: onClose
            )
        }
        .padding(20)
        .frame(width: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenWelcomeWindow"))) { _ in
            openWindow(id: "WelcomeWindow")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ruma")
                    .font(.title.bold())
                    .foregroundStyle(.primary)
                
                Text("AI Assistant")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
    
            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.modelReady ? .green : .orange)
                    .frame(width: 10, height: 10)
                
                Text(appState.modelReady ? "Ready" : "Loading")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
}

// MARK: - Preferences Sheet
struct PreferencesSheet: View {
    @ObservedObject var userSettings: UserSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var tempUsername: String = ""
    @State private var isRecordingHotkey = false
    @State private var tempModifiers: NSEvent.ModifierFlags = []
    @State private var tempKeyCode: UInt16? = nil
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Fixed Header
            VStack(spacing: 8) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.blue)
                
                Text("Preferences")
                    .font(.title.bold())
                
                Text("Customize your Ruma experience")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 24)
            
            // Scrollable Content
            ScrollView {
                VStack(spacing: 20) {
                    // Username Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        TextField("Enter your name", text: $tempUsername)
                            .textFieldStyle(.roundedBorder)
                            .font(.body)
                            .focused($isTextFieldFocused)
                            .onSubmit {
                                saveUsername()
                            }
                    }
                    
                    // Hotkey Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Hotkey")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        
                        VStack(spacing: 12) {
                            if isRecordingHotkey {
                                Text("Press your desired key combination...")
                                    .font(.body)
                                    .foregroundStyle(.orange)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text(tempKeyCode != nil ? formatHotkey(modifiers: tempModifiers, keyCode: tempKeyCode!) : userSettings.customHotkeyDisplay)
                                    .font(.title3.monospaced().weight(.medium))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            }
                            
                            HStack(spacing: 12) {
                                Button("Record Hotkey") {
                                    isRecordingHotkey = true
                                    tempModifiers = []
                                    tempKeyCode = nil
                                }
                                .buttonStyle(.bordered)
                                .disabled(isRecordingHotkey)
                                
                                Button("Reset to Default") {
                                    userSettings.resetHotkeyToDefault()
                                    tempModifiers = userSettings.customHotkeyModifiers
                                    tempKeyCode = userSettings.customHotkeyKeyCode
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    // Reset Settings Section
                    VStack(spacing: 8) {
                        Divider()
                        
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            
                            Text("Reset all settings to default values")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Button("Reset All Settings") {
                            userSettings.resetAllSettings()
                            // Update temp values to reflect the reset
                            tempUsername = userSettings.username
                            tempModifiers = userSettings.customHotkeyModifiers
                            tempKeyCode = userSettings.customHotkeyKeyCode
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .foregroundStyle(.orange)
                    }
                    .padding(.top, 20)
                    
                    // Add some bottom padding for scrolling
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 32)
            }
            
            // Fixed Action Buttons
            VStack(spacing: 0) {
                Divider()
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    
                    Button("Save Changes") {
                        saveChanges()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding(.top, 16)
            }
        }
        .padding(32)
        .frame(width: 450, height: 550)
        .onAppear {
            tempUsername = userSettings.username
            tempModifiers = userSettings.customHotkeyModifiers
            tempKeyCode = userSettings.customHotkeyKeyCode
            isTextFieldFocused = true
        }
        .background(KeyEventHandling { event in
            if isRecordingHotkey {
                tempModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                tempKeyCode = event.keyCode
                isRecordingHotkey = false
                return true
            }
            return false
        })
        .background(.ultraThinMaterial)
    }
    
    private func saveUsername() {
        let trimmed = tempUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            userSettings.setUsername(trimmed)
        }
    }
    
    private func saveChanges() {
        // Save username
        saveUsername()
        
        // Save hotkey
        if let keyCode = tempKeyCode {
            userSettings.setCustomHotkey(modifiers: tempModifiers, keyCode: keyCode)
        }
    }
    
    private func formatHotkey(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) -> String {
        var components: [String] = []
        
        if modifiers.contains(.command) { components.append("⌘") }
        if modifiers.contains(.option) { components.append("⌥") }
        if modifiers.contains(.control) { components.append("⌃") }
        if modifiers.contains(.shift) { components.append("⇧") }
        
        components.append(keyCodeToString(keyCode))
        return components.joined()
    }
    
    private func keyCodeToString(_ keyCode: UInt16) -> String {
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 22: return "6"
        case 23: return "5"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        default: return "Key\(keyCode)"
        }
    }
}
    

// MARK: - Menu Button Component
struct MenuButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? color.opacity(0.1) : Color.clear)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(color.opacity(isHovered ? 0.3 : 0.2), lineWidth: 1)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            )
        }
        .buttonStyle(.borderless)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Key Event Handling
struct KeyEventHandling: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onKeyDown = onKeyDown
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class KeyView: NSView {
    var onKeyDown: ((NSEvent) -> Bool)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if let handler = onKeyDown, handler(event) {
            return
        }
        super.keyDown(with: event)
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

// MARK: - AppDelegate Extensions for Window Management
extension AppDelegate {
    @objc func openModelHub() {
        // Open Model Hub window
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "ModelHubWindow" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSApp.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
        }
    }
    
    @objc func openMemoryManagement() {
        // Open Memory Management window
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "MemoryManagementWindow" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSApp.orderFrontStandardAboutPanel(_:)), to: nil, from: nil)
        }
    }
}
