//
//  ScreenCaptureTypes.swift  
//  SuriAI - Shared Screen Capture Types
//
//  Created by Claude on 02/07/25.
//

import SwiftUI
import Foundation

// Simplified screen intelligence result
struct ScreenIntelligenceResult {
    let analysis: String
    let success: Bool
    let processingTime: TimeInterval
    
    static func success(_ analysis: String, processingTime: TimeInterval = 0) -> ScreenIntelligenceResult {
        return ScreenIntelligenceResult(analysis: analysis, success: true, processingTime: processingTime)
    }
    
    static func failure(_ error: String) -> ScreenIntelligenceResult {
        return ScreenIntelligenceResult(analysis: error, success: false, processingTime: 0)
    }
}

// MARK: - Supporting Data Structures

public struct ScreenCaptureResult {
    let image: NSImage
    let extractedText: String
    let windowInfo: WindowInfo?
    let timestamp: Date
    let visionAnalysis: VisionAnalysisResult?
    
    var hasText: Bool {
        !extractedText.isEmpty
    }
    
    var hasImage: Bool {
        image.size.width > 0 && image.size.height > 0
    }
    
    var contextDescription: String {
        var description = "Screen capture from \(windowInfo?.appName ?? "Unknown")"
        if let windowInfo = windowInfo, !windowInfo.title.isEmpty && windowInfo.title != "Unknown" {
            description += " - \(windowInfo.title)"
        }
        
        if hasText {
            description += "\n\nExtracted text:\n\(extractedText)"
        }
        
        if hasImage {
            description += "\n\nVisual content: Image captured successfully (\(Int(image.size.width))x\(Int(image.size.height)) pixels)"
        }
        
        return description
    }
}

public struct WindowInfo {
    let title: String
    let appName: String
    let bounds: CGRect
}

// MARK: - Screen Capture Manager for older macOS versions

public class LegacyScreenCapture: ObservableObject {
    @Published var lastCapturedImage: NSImage?
    @Published var captureError: String?
    
    public func captureScreen() -> ScreenCaptureResult? {
        // Fallback for macOS < 12.3 using different approach
        captureError = "Legacy screen capture not implemented. Please upgrade to macOS 12.3+ for full screen capture functionality."
        return nil
    }
}