//
//  FloatingWindow2App.swift
//  FloatingWindow2
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI
import AppKit

@main
struct SuriAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var userSettings = UserSettings.shared
    @StateObject private var personalityManager = PersonalityManager()
    @StateObject private var dynamicPlacementManager = DynamicIslandPlacementManager.shared
    @StateObject private var screenCaptureManager = ScreenCaptureManager()
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        
        MenuBarExtra{
            MenuBarView(
                personalityManager: personalityManager,
                dynamicPlacementManager: dynamicPlacementManager,
                screenCaptureManager: screenCaptureManager,
                appState: appState,
                userSettings: userSettings,
                onCreateNewChat: {
                    appDelegate.showContentPanel()
                },
                onToggleChatHistory: {
                    // Handle chat history toggle
                },
                onToggleDynamicMode: {
                    dynamicPlacementManager.toggleDynamicMode()
                },
                onClose: {
                    NSApplication.shared.terminate(nil)
                }
            )
            .onAppear {
                // Show welcome window for first-time users
                if userSettings.isFirstLaunch {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Use notification to trigger window opening since we can't access openWindow here
                        NotificationCenter.default.post(name: NSNotification.Name("OpenWelcomeWindow"), object: nil)
                    }
                }
                
                Task {
                    do {
                        try await waitForModelReady()
                        await MainActor.run {
                            appState.modelReady = true
                        }
                        await personalityManager.loadPersonalities()
                    } catch {
                        print("❌ Model failed to load in MenuBar: \(error)")
                        // Set as ready anyway for MenuBar to work
                        await MainActor.run {
                            appState.modelReady = true
                        }
                    }
                }
            }
        }label: {
            Label("Ruma", image: "menuBarLogo")
        }
        
        
        
        // Define the second window here
        WindowGroup("Model Hub", id: "ModelHubWindow") {
            if #available(macOS 15.0, *) {
                ModelHubView()
                    .containerBackground(.clear, for: .window)
                    .preferredColorScheme(.dark)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Model Hub" }) {
                                
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            } else {
                ModelHubView()
                    .background(Color.clear)
                    .preferredColorScheme(.dark)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Model Hub" }) {
                                
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        
        // Memory Management Window
        WindowGroup("Memory Management", id: "MemoryManagementWindow") {
            if #available(macOS 15.0, *) {
                MemoryManagementView()
                    .preferredColorScheme(.dark)
                    .containerBackground(.clear, for: .window)
                    .frame(minWidth: 800, minHeight: 600)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Memory Management" }) {
                                
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            } else {
                MemoryManagementView()
                    .preferredColorScheme(.dark)
                    .background(Color.clear)
                    .frame(minWidth: 800, minHeight: 600)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Memory Management" }) {
                                
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            }
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        
        // Preferences Window
        WindowGroup("Preferences", id: "PreferencesWindow") {
            if #available(macOS 15.0, *) {
                PreferencesSheet(userSettings: userSettings)
                    .preferredColorScheme(.dark)
                    .containerBackground(.clear, for: .window)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Preferences" }) {
                                window.level = .floating
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            } else {
                PreferencesSheet(userSettings: userSettings)
                    .preferredColorScheme(.dark)
                    .background(Color.clear)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Preferences" }) {
                                window.level = .floating
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(HiddenTitleBarWindowStyle())
        
        // Welcome Window for First Launch
        WindowGroup("Welcome", id: "WelcomeWindow") {
            if #available(macOS 15.0, *) {
                WelcomeWindowContent(userSettings: userSettings)
                    .preferredColorScheme(.dark)
                    .containerBackground(.clear, for: .window)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Welcome" }) {
                                window.level = .floating
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            } else {
                WelcomeWindowContent(userSettings: userSettings)
                    .preferredColorScheme(.dark)
                    .background(Color.clear)
                    .onAppear {
                        // Force window to front when it appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let window = NSApp.windows.first(where: { $0.title == "Welcome" }) {
                                window.level = .floating
                                window.makeKeyAndOrderFront(nil)
                                NSApp.activate(ignoringOtherApps: true)
                            }
                        }
                    }
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(HiddenTitleBarWindowStyle())
        
//        .windowResizability(.contentSize)
    }
}




