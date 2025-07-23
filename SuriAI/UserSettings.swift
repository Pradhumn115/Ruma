//
//  UserSettings.swift
//  SuriAI - User Preferences and Settings
//
//  Created by Claude on 06/07/25.
//

import SwiftUI
import AppKit
import HotKey

class UserSettings: ObservableObject {
    static let shared = UserSettings()
    
    @Published var username: String = "User"
    @Published var isFirstLaunch: Bool = true
    @Published var customHotkeyModifiers: NSEvent.ModifierFlags = [.command, .shift]
    @Published var customHotkeyKeyCode: UInt16 = 0 // 'a' key
    
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private let usernameKey = "com.ruma.username"
    private let firstLaunchKey = "com.ruma.firstLaunch"
    private let hotkeyModifiersKey = "com.ruma.hotkeyModifiers"
    private let hotkeyKeyCodeKey = "com.ruma.hotkeyKeyCode"
    
    private init() {
        loadSettings()
    }
    
    // MARK: - Settings Management
    private func loadSettings() {
        // Load username
        if let savedUsername = userDefaults.string(forKey: usernameKey), !savedUsername.isEmpty {
            username = savedUsername.lowercased()
            isFirstLaunch = false
        } else {
            isFirstLaunch = userDefaults.object(forKey: firstLaunchKey) == nil
        }
        
        // Load hotkey settings
        if userDefaults.object(forKey: hotkeyModifiersKey) != nil {
            let modifiersRawValue = userDefaults.integer(forKey: hotkeyModifiersKey)
            customHotkeyModifiers = NSEvent.ModifierFlags(rawValue: UInt(modifiersRawValue))
            customHotkeyKeyCode = UInt16(userDefaults.integer(forKey: hotkeyKeyCodeKey))
        }
    }
    
    private func saveSettings() {
        print("💾 Saving user settings...")
        userDefaults.set(username, forKey: usernameKey)
        userDefaults.set(false, forKey: firstLaunchKey)
        userDefaults.set(Int(customHotkeyModifiers.rawValue), forKey: hotkeyModifiersKey)
        userDefaults.set(Int(customHotkeyKeyCode), forKey: hotkeyKeyCodeKey)
        userDefaults.synchronize()
        print("✅ Settings saved successfully")
    }
    
    // MARK: - Username Management
    func setUsername(_ newUsername: String) {
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { return }
        
        username = trimmedUsername.lowercased()
        isFirstLaunch = false
        saveSettings()
    }
    
    func completeFirstLaunch() {
        isFirstLaunch = false
        saveSettings()
    }
    
    // Combined method for first launch setup to avoid duplicate saves
    func setUsernameAndCompleteFirstLaunch(_ newUsername: String) {
        let trimmedUsername = newUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty else { return }
        
        print("👤 Setting username to: \(trimmedUsername) and completing first launch")
        username = trimmedUsername.lowercased()
        isFirstLaunch = false
        saveSettings()
    }
    
    // MARK: - Hotkey Management
    func setCustomHotkey(modifiers: NSEvent.ModifierFlags, keyCode: UInt16) {
        customHotkeyModifiers = modifiers
        customHotkeyKeyCode = keyCode
        saveSettings()
        
        // Notify AppDelegate of hotkey change
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeyDidChange"),
            object: nil,
            userInfo: [
                "modifiers": modifiers,
                "keyCode": keyCode
            ]
        )
    }
    
    func resetHotkeyToDefault() {
        customHotkeyModifiers = [.command, .shift]
        customHotkeyKeyCode = 1 // 's' key
        saveSettings()
        
        // Notify AppDelegate of hotkey change
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeyDidChange"),
            object: nil,
            userInfo: [
                "modifiers": customHotkeyModifiers,
                "keyCode": customHotkeyKeyCode
            ]
        )
    }
    
    // MARK: - Reset All Settings
    func resetAllSettings() {
        // Remove all UserDefaults
        UserDefaults.standard.removeObject(forKey: usernameKey)
        UserDefaults.standard.removeObject(forKey: firstLaunchKey)
        UserDefaults.standard.removeObject(forKey: hotkeyModifiersKey)
        UserDefaults.standard.removeObject(forKey: hotkeyKeyCodeKey)
        UserDefaults.standard.removeObject(forKey: "HasLaunchedBefore")
        UserDefaults.standard.synchronize()
        
        // Reset to defaults
        username = "User"
        isFirstLaunch = true
        customHotkeyModifiers = [.command, .shift]
        customHotkeyKeyCode = 0 // 'a' key
        
        // Notify AppDelegate of hotkey change
        NotificationCenter.default.post(
            name: NSNotification.Name("HotkeyDidChange"),
            object: nil,
            userInfo: [
                "modifiers": customHotkeyModifiers,
                "keyCode": customHotkeyKeyCode
            ]
        )
        
        print("✅ All user settings have been reset to defaults")
    }
    
    var customHotkeyDisplay: String {
        var components: [String] = []
        
        if customHotkeyModifiers.contains(.command) {
            components.append("⌘")
        }
        if customHotkeyModifiers.contains(.option) {
            components.append("⌥")
        }
        if customHotkeyModifiers.contains(.control) {
            components.append("⌃")
        }
        if customHotkeyModifiers.contains(.shift) {
            components.append("⇧")
        }
        
        // Convert keyCode to readable key name
        let keyName = keyCodeToString(customHotkeyKeyCode)
        components.append(keyName)
        
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
        case 24: return "="
        case 25: return "9"
        case 26: return "7"
        case 27: return "-"
        case 28: return "8"
        case 29: return "0"
        case 30: return "]"
        case 31: return "O"
        case 32: return "U"
        case 33: return "["
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 39: return "'"
        case 40: return "K"
        case 41: return ";"
        case 42: return "\\"
        case 43: return ","
        case 44: return "/"
        case 45: return "N"
        case 46: return "M"
        case 47: return "."
        case 49: return "Space"
        case 50: return "`"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key\(keyCode)"
        }
    }
    
    // MARK: - HotKey Integration
    func createHotKey(handler: @escaping () -> Void) -> HotKey? {
        let key = Key(carbonKeyCode: UInt32(customHotkeyKeyCode))
        let modifiers = convertToHotKeyModifiers(customHotkeyModifiers)
        
        guard let key = key else { return nil }
        
        let hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey.keyDownHandler = handler
        
        return hotKey
    }
    
    private func convertToHotKeyModifiers(_ nsModifiers: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        var hotKeyModifiers: NSEvent.ModifierFlags = []
        
        if nsModifiers.contains(.command) {
            hotKeyModifiers.insert(.command)
        }
        if nsModifiers.contains(.option) {
            hotKeyModifiers.insert(.option)
        }
        if nsModifiers.contains(.control) {
            hotKeyModifiers.insert(.control)
        }
        if nsModifiers.contains(.shift) {
            hotKeyModifiers.insert(.shift)
        }
        
        return hotKeyModifiers
    }
}

// MARK: - First Launch Setup View
struct FirstLaunchSetupView: View {
    @ObservedObject var userSettings: UserSettings
    @State private var tempUsername: String = ""
    
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)
                
                Text("Welcome to Ruma!")
                    .font(.largeTitle.bold())
                
                Text("Let's get you set up with a personalized AI experience")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("What should we call you?")
                    .font(.headline)
                
                TextField("Enter your name", text: $tempUsername)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .onSubmit {
                        if canProceed {
                            completeSetup()
                        }
                    }
                
                Text("This name will be used throughout the app and can be changed later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                completeSetup()
            } label: {
                HStack {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(canProceed ? Color.blue : Color.gray)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(!canProceed)
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .background(Material.thick)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 8)
    }
    
    private var canProceed: Bool {
        !tempUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func completeSetup() {
        guard canProceed else { return }
        
        print("🔄 Starting first launch setup completion...")
        
        let trimmedUsername = tempUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Use combined method to avoid duplicate saves
        userSettings.setUsernameAndCompleteFirstLaunch(trimmedUsername)
        
        print("🚀 Calling onComplete closure...")
        DispatchQueue.main.async {
            self.onComplete()
        }
    }
}

// MARK: - Welcome Window Content
struct WelcomeWindowContent: View {
    @ObservedObject var userSettings: UserSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        FirstLaunchSetupView(userSettings: userSettings) {
            // Close the window when setup is complete
            dismiss()
        }
    }
}
