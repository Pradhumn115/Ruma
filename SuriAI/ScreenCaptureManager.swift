//
//  ScreenCaptureManager.swift
//  SuriAI - Simplified Screen Capture and Analysis
//
//  Created by Claude on 02/07/25.
//

import SwiftUI
import Foundation
import ScreenCaptureKit

@MainActor
class ScreenCaptureManager: ObservableObject {
    @Published var isAvailable = false
    @Published var isAnalyzing = false
    @Published var lastError: String?
    
    private var screenCapture: ScreenCaptureService?
    private var appleVision: AppleVisionOCR?
    
    init() {
        // Don't setup capture immediately - wait for user to enable screen reasoning
        if #available(macOS 12.3, *) {
            print("📱 Screen capture available (not initialized yet)")
            isAvailable = true
        } else {
            print("⚠️ Screen capture requires macOS 12.3+")
            isAvailable = false
        }
    }
    
    private func setupCaptureIfNeeded() async {
        guard screenCapture == nil else { return } // Already initialized
        
        if #available(macOS 12.3, *) {
            screenCapture = ScreenCaptureService()
            appleVision = AppleVisionOCR()
            
            // Request permissions only when actually needed
            await screenCapture?.requestScreenCapturePermissions()
            await screenCapture?.refreshAvailableContent()
            
            isAvailable = screenCapture?.isScreenCaptureAvailable ?? false
            print("✅ Screen capture initialized with user consent")
        }
    }
    
    // MARK: - Main Public Methods
    
    func refreshScreenPermissions() async {
        // Initialize screen capture if not already done (this will request permission)
        await setupCaptureIfNeeded()
        isAvailable = screenCapture?.isScreenCaptureAvailable ?? false
    }
    
    func analyzeScreenContent(userQuestion: String, userID: String, chatID: String) async -> String {
        return await performAnalysis(userQuestion: userQuestion, userID: userID, chatID: chatID, streaming: false)
    }
    
    func streamScreenAnalysis(userQuestion: String, userID: String, chatID: String, onChunk: @escaping (String) -> Void) async {
        _ = await performAnalysis(userQuestion: userQuestion, userID: userID, chatID: chatID, streaming: true, onChunk: onChunk)
    }
    
    // MARK: - Core Analysis Logic
    
    private func performAnalysis(userQuestion: String, userID: String, chatID: String, streaming: Bool, onChunk: ((String) -> Void)? = nil) async -> String {
        // Initialize capture if needed (this will request permission if first time)
        await setupCaptureIfNeeded()
        
        guard isAvailable, let screenCapture = screenCapture, let appleVision = appleVision else {
            return "Screen capture not available. Please grant screen recording permission in System Settings > Privacy & Security > Screen Recording."
        }
        
        isAnalyzing = true
        defer { isAnalyzing = false }
        
        do {
            // Step 1: Capture screen
            guard let captureResult = await screenCapture.captureActiveWindow() else {
                throw ScreenCaptureError.captureFailure("Failed to capture screen")
            }
            
            // Step 2: Analyze with Apple Vision (OCR + Visual Look Up)
            guard let visionResult = await appleVision.analyzeImage(captureResult.image) else {
                throw ScreenCaptureError.visionFailure("Apple Vision analysis failed")
            }
            print(visionResult)
            // Step 3: Send to backend for enhanced analysis
            // Convert NSImage to Data for vision processing
            let imageData = captureResult.image.tiffRepresentation.flatMap { tiffData in
                NSBitmapImageRep(data: tiffData)?.representation(using: .jpeg, properties: [:])
            }
            
            let analysis = await sendToBackend(
                question: userQuestion,
                textContent: visionResult.extractedText,
                userID: userID,
                useVision: true, // Enable vision for enhanced analysis
                imageData: imageData
            )
            
            return analysis
            
        } catch {
            let errorMessage = "Analysis failed: \(error.localizedDescription)"
            lastError = errorMessage
            return errorMessage
        }
    }
    
    // MARK: - Backend Integration
    
    private func sendToBackend(question: String, textContent: String, userID: String, useVision: Bool = false, imageData: Data? = nil) async -> String {
        let baseURL = serverConfig.currentServerURL
        let url = URL(string: "\(baseURL)/analyze_image")!
        
        var payload: [String: Any] = [
            "question": question,
            "text_content": textContent,
            "user_id": userID,
            "use_vision": useVision
        ]
        
        // Add base64 encoded image data if vision is enabled
        if useVision, let imageData = imageData {
            let base64Image = imageData.base64EncodedString()
            payload["image_data"] = base64Image
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            if let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let analysis = response["analysis"] as? String {
                return analysis
            }
            
            return "Backend analysis not available"
            
        } catch {
            print("Backend error: \(error)")
            // Fallback to just showing the extracted text
            return "I can see the screen content:\n\n\(textContent)\n\nPlease ask specific questions about what you're seeing."
        }
    }
}

// MARK: - Error Types

enum ScreenCaptureError: Error {
    case captureFailure(String)
    case visionFailure(String)
    case backendFailure(String)
    
    var localizedDescription: String {
        switch self {
        case .captureFailure(let message):
            return "Screen capture failed: \(message)"
        case .visionFailure(let message):
            return "Vision analysis failed: \(message)"
        case .backendFailure(let message):
            return "Backend analysis failed: \(message)"
        }
    }
}



