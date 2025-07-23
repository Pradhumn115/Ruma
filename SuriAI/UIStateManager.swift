//
//  UIStateManager.swift
//  SuriAI
//
//  Created by AI Assistant on 03/07/25.
//

import Foundation
import AppKit
import SwiftUI

class UIStateManager: ObservableObject {
    static let shared = UIStateManager()
    
    @Published var isUIActive = false
    
    private init() {
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        // Using ONLY ContentView onAppear/onDisappear - no automatic notifications
        print("🔍 UIStateManager initialized - ContentView tracking only")
    }
    
    private func setUIActive(_ active: Bool) {
        // Simple immediate state change
        guard active != isUIActive else { 
            print("🔍 UI State already \(active ? "ACTIVE" : "INACTIVE") - no change needed")
            return 
        }
        
        DispatchQueue.main.async {
            self.isUIActive = active
            print("🔍 UI State changed to: \(active ? "ACTIVE" : "INACTIVE")")
            
            // Notify backend about UI state change
            Task {
                await self.notifyBackendUIStatus(active)
            }
        }
    }
    
    private func notifyBackendUIStatus(_ isActive: Bool) async {
        do {
            let url = URL(string: "\(serverConfig.currentServerURL)/ui/status")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["is_active": isActive]
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let message = responseData["message"] as? String {
                        print("✅ Backend UI status updated: \(message)")
                    }
                } else {
                    print("⚠️ Failed to update backend UI status: HTTP \(httpResponse.statusCode)")
                }
            }
        } catch {
            print("❌ Error notifying backend of UI status: \(error)")
        }
    }
    
    // Manual methods for explicit UI state changes
    func forceUIActive() {
        print("🔍 Manually setting UI active")
        setUIActive(true)
    }
    
    func forceUIInactive() {
        print("🔍 Manually setting UI inactive")
        setUIActive(false)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - SwiftUI Integration

extension UIStateManager {
    /// Call this when ContentView appears
    func contentViewDidAppear() {
        print("🔍 ContentView appeared")
        forceUIActive()
    }
    
    /// Call this when ContentView disappears
    func contentViewDidDisappear() {
        print("🔍 ContentView disappeared")
        forceUIInactive()
    }
    
    /// Call this when Dynamic Island appears (no state change - ContentView handles it)
    func dynamicIslandDidAppear() {
        print("🔍 Dynamic Island appeared (no state change)")
        // Don't change UI state - let ContentView handle it
    }
    
    /// Call this when Dynamic Island disappears (no state change - ContentView handles it)
    func dynamicIslandDidDisappear() {
        print("🔍 Dynamic Island disappeared (no state change)")
        // Don't change UI state - let ContentView handle it
    }
}
