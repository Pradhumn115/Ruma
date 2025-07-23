//
//  ScreenCaptureService.swift
//  SuriAI - Advanced Screen Capture and Analysis
//
//  Created by Pradhumn Gupta on 30/06/25.
//

import SwiftUI
import ScreenCaptureKit
import AVFoundation
import Vision
import CoreImage

@available(macOS 12.3, *)
@MainActor
class ScreenCaptureService: ObservableObject {
    @Published var isScreenCaptureAvailable = false
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var isCapturing = false
    @Published var lastCapturedImage: NSImage?
    @Published var extractedText: String = ""
    @Published var captureError: String?
    @Published var visionAnalysisResult: VisionAnalysisResult?
    
    private var contentFilter: SCContentFilter?
    private var streamConfiguration: SCStreamConfiguration?
    private var appleVisionOCR: AppleVisionOCR?
    
    init() {
        // Initialize Apple Vision OCR
        if #available(macOS 11.0, *) {
            appleVisionOCR = AppleVisionOCR()
        }
        
        // Don't request permissions immediately - only when user actually needs screen reasoning
        print("📸 ScreenCaptureService initialized (permissions not requested yet)")
    }
    
    // MARK: - Permissions
    
    func requestScreenCapturePermissions() async {
        do {
            // Request screen recording permission
            let hasPermission = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            isScreenCaptureAvailable = !hasPermission.displays.isEmpty
            
            if !isScreenCaptureAvailable {
                captureError = "Screen capture permission denied. Please enable in System Preferences > Security & Privacy > Screen Recording"
            }
        } catch {
            captureError = "Failed to request screen capture permissions: \(error.localizedDescription)"
            isScreenCaptureAvailable = false
        }
    }
    
    // MARK: - Content Discovery
    
    func refreshAvailableContent() async {
        guard isScreenCaptureAvailable else { return }
        
        do {
            let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            
            availableDisplays = shareableContent.displays
            availableWindows = shareableContent.windows.filter { window in
                // Filter out system windows and empty titles
                guard let windowTitle = window.title, !windowTitle.isEmpty else { return false }
                guard let appName = window.owningApplication?.applicationName, !appName.isEmpty else { return false }
                
                // Exclude system apps and our own app
                let excludedApps = ["WindowServer", "Dock", "Control Center", "NotificationCenter", "Ruma"]
                return !excludedApps.contains(appName)
            }
            
            print("📺 Found \(availableDisplays.count) displays and \(availableWindows.count) windows")
            
        } catch {
            captureError = "Failed to get shareable content: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Screen Capture
    
    func captureFullScreen() async -> ScreenCaptureResult? {
        guard !availableDisplays.isEmpty else {
            captureError = "No displays available for capture"
            return nil
        }
        
        return await captureDisplay(availableDisplays[0])
    }
    
    func captureActiveWindow() async -> ScreenCaptureResult? {
        // Get the frontmost window
        if let frontWindow = await getFrontmostWindow() {
            let appName = frontWindow.owningApplication?.applicationName ?? ""
            
            // Special handling for Preview and other image viewers
            if appName.contains("Preview") || appName.contains("Photos") {
                print("🖼️ Detected \(appName) - using optimized capture for image viewer")
                
                // Add small delay to ensure Preview has finished rendering
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            var result = await captureWindow(frontWindow)
            
            // Enhanced web content extraction for browsers
            if let windowResult = result, isBrowserWindow(frontWindow) {
                let enhancedResult = await enhanceWebContent(for: windowResult, window: frontWindow)
                result = enhancedResult
            }
            
            return result
        } else {
            // Fallback to full screen if no specific window found
            return await captureFullScreen()
        }
    }
    
    func captureWindow(_ window: SCWindow) async -> ScreenCaptureResult? {
        guard isScreenCaptureAvailable else {
            captureError = "Screen capture not available"
            return nil
        }
        
        isCapturing = true
        captureError = nil
        
        do {
            // Create content filter for the specific window
            let filter = SCContentFilter(desktopIndependentWindow: window)
            
            // Configure the stream with improved settings for Preview app compatibility
            let configuration = SCStreamConfiguration()
            configuration.width = Int(window.frame.width * 2) // Retina scaling
            configuration.height = Int(window.frame.height * 2)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS
            configuration.queueDepth = 5
            
            // Use different pixel format for Preview app to avoid color space issues
            let appName = window.owningApplication?.applicationName ?? ""
            if appName.contains("Preview") || appName.contains("Photos") {
                print("🖼️ Detected image viewer app (\(appName)) - using RGB pixel format")
                configuration.pixelFormat = kCVPixelFormatType_32ARGB // Better for image viewers
            } else {
                configuration.pixelFormat = kCVPixelFormatType_32BGRA // Standard format
            }
            
            // Force consistent color space handling
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.showsCursor = false // Avoid cursor interference
            
            // Capture a single frame
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            lastCapturedImage = nsImage
            
            // Use Apple Vision for enhanced text extraction
            let visionResult = await performAdvancedVisionAnalysis(nsImage)
            let extractedText: String
            if let visionExtractedText = visionResult?.extractedText {
                extractedText = visionExtractedText
            } else {
                extractedText = await extractTextFromImage(image)
            }
            
            // Store vision result for potential API calls
            self.visionAnalysisResult = visionResult
            
            // Create enhanced result with structured data
            let result = ScreenCaptureResult(
                image: nsImage,
                extractedText: extractedText,
                windowInfo: WindowInfo(
                    title: window.title ?? "Unknown",
                    appName: window.owningApplication?.applicationName ?? "Unknown",
                    bounds: window.frame
                ),
                timestamp: Date(),
                visionAnalysis: visionResult  // Pass structured vision data
            )
            
            isCapturing = false
            return result
            
        } catch {
            captureError = "Failed to capture window: \(error.localizedDescription)"
            isCapturing = false
            return nil
        }
    }
    
    func captureDisplay(_ display: SCDisplay) async -> ScreenCaptureResult? {
        guard isScreenCaptureAvailable else {
            captureError = "Screen capture not available"
            return nil
        }
        
        isCapturing = true
        captureError = nil
        
        do {
            // Create content filter for the display
            let filter = SCContentFilter(display: display, excludingWindows: [])
            
            // Configure the stream
            let configuration = SCStreamConfiguration()
            configuration.width = display.width * 2 // Retina scaling
            configuration.height = display.height * 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            configuration.queueDepth = 5
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            
            // Capture a single frame
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            
            let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            lastCapturedImage = nsImage
            
            // Use Apple Vision for enhanced text extraction
            let visionResult = await performAdvancedVisionAnalysis(nsImage)
            let extractedText: String
            if let visionExtractedText = visionResult?.extractedText {
                extractedText = visionExtractedText
            } else {
                extractedText = await extractTextFromImage(image)
            }
            
            // Store vision result for potential API calls
            self.visionAnalysisResult = visionResult
            
            // Create enhanced result with structured data
            let result = ScreenCaptureResult(
                image: nsImage,
                extractedText: extractedText,
                windowInfo: nil, // No specific window for full display
                timestamp: Date(),
                visionAnalysis: visionResult  // Pass structured vision data
            )
            
            isCapturing = false
            return result
            
        } catch {
            captureError = "Failed to capture display: \(error.localizedDescription)"
            isCapturing = false
            return nil
        }
    }
    
    // MARK: - Window Management
    
    private func getFrontmostWindow() async -> SCWindow? {
        await refreshAvailableContent()
        
        // Get frontmost application
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
        
        // Find the frontmost window of that application
        return availableWindows.first { window in
            window.owningApplication?.applicationName == frontApp.localizedName
        }
    }
    
    // MARK: - Web Content Enhancement
    
    private func isBrowserWindow(_ window: SCWindow) -> Bool {
        guard let appName = window.owningApplication?.applicationName else { return false }
        let browserApps = ["Safari", "Google Chrome", "Firefox", "Microsoft Edge", "Arc", "Brave Browser", "Opera"]
        return browserApps.contains(appName)
    }
    
    private func enhanceWebContent(for result: ScreenCaptureResult, window: SCWindow) async -> ScreenCaptureResult {
        guard let appName = window.owningApplication?.applicationName else { return result }
        
        let enhancedText = result.extractedText
        var webContext = ""
        
        // Try to extract URL and additional web context
        if let urlInfo = await extractWebURL(from: appName, windowTitle: window.title ?? "") {
            webContext += "URL: \(urlInfo.url)\n"
            if !urlInfo.pageTitle.isEmpty {
                webContext += "Page Title: \(urlInfo.pageTitle)\n"
            }
        }
        
        // Enhanced text extraction with web-specific processing
        let webEnhancedText = await processWebContent(enhancedText)
        
        // Combine all information
        let combinedText = """
        \(webContext.isEmpty ? "" : "WEB CONTEXT:\n\(webContext)\n")TEXT CONTENT:
        \(webEnhancedText)
        
        VISUAL ELEMENTS DETECTED:
        \(result.extractedText)
        """
        
        return ScreenCaptureResult(
            image: result.image,
            extractedText: combinedText,
            windowInfo: result.windowInfo,
            timestamp: result.timestamp,
            visionAnalysis: result.visionAnalysis
        )
    }
    
    private func extractWebURL(from appName: String, windowTitle: String) async -> (url: String, pageTitle: String)? {
        // Use AppleScript to get current URL from browsers
        let script: String
        
        switch appName {
        case "Safari":
            script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    set currentTab to current tab of front window
                    return (URL of currentTab) & " | " & (name of currentTab)
                end if
            end tell
            """
        case "Google Chrome":
            script = """
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    set currentTab to active tab of front window
                    return (URL of currentTab) & " | " & (title of currentTab)
                end if
            end tell
            """
        case "Firefox":
            // Firefox doesn't support AppleScript as well, fallback to window title parsing
            return parseURLFromTitle(windowTitle)
        default:
            return parseURLFromTitle(windowTitle)
        }
        
        if let result = await runAppleScript(script), !result.isEmpty {
            let components = result.components(separatedBy: " | ")
            if components.count >= 2 {
                return (url: components[0], pageTitle: components[1])
            } else {
                return (url: result, pageTitle: "")
            }
        }
        
        return parseURLFromTitle(windowTitle)
    }
    
    private func parseURLFromTitle(_ title: String) -> (url: String, pageTitle: String)? {
        // Try to extract URL from window title (many browsers show URL in title)
        let urlRegex = try? NSRegularExpression(pattern: #"https?://[^\s]+"#)
        if let regex = urlRegex,
           let match = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) {
            let url = String(title[Range(match.range, in: title)!])
            let pageTitle = title.replacingOccurrences(of: url, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (url: url, pageTitle: pageTitle)
        }
        
        return nil
    }
    
    private func runAppleScript(_ script: String) async -> String? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let appleScript = NSAppleScript(source: script)
                var error: NSDictionary?
                let result = appleScript?.executeAndReturnError(&error)
                
                if let error = error {
                    print("❌ AppleScript error: \(error)")
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: result?.stringValue)
                }
            }
        }
    }
    
    private func processWebContent(_ text: String) async -> String {
        // Enhanced text processing for web content
        var processedText = text
        
        // Remove excessive whitespace and normalize
        processedText = processedText.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        // Try to identify common web elements
        let webElements = identifyWebElements(in: processedText)
        if !webElements.isEmpty {
            processedText += "\n\nIDENTIFIED WEB ELEMENTS:\n" + webElements.joined(separator: "\n")
        }
        
        return processedText
    }
    
    private func identifyWebElements(in text: String) -> [String] {
        var elements: [String] = []
        
        // Common web UI patterns
        let patterns = [
            (#"(?i)(login|sign in|log in)"#, "Login/Authentication element"),
            (#"(?i)(search|find)"#, "Search functionality"),
            (#"(?i)(menu|navigation|nav)"#, "Navigation element"),
            (#"(?i)(button|btn|click)"#, "Interactive button"),
            (#"(?i)(form|input|field)"#, "Form element"),
            (#"(?i)(cart|checkout|buy|purchase)"#, "E-commerce element"),
            (#"(?i)(profile|account|settings)"#, "User account element"),
            (#"(?i)(home|dashboard|main)"#, "Main page element")
        ]
        
        for (pattern, description) in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
                elements.append("• \(description)")
            }
        }
        
        return elements
    }
    
    // MARK: - Apple Vision Analysis
    
    private func performAdvancedVisionAnalysis(_ image: NSImage) async -> VisionAnalysisResult? {
        guard #available(macOS 11.0, *), let visionOCR = appleVisionOCR else {
            print("⚠️ Apple Vision OCR not available, falling back to basic Vision")
            return nil
        }
        
        print("🔍 Performing Apple Vision analysis...")
        let result = await visionOCR.analyzeImage(image)
        
        if let result = result {
            print("✅ Apple Vision analysis completed:")
            print("   📝 Text regions: \(result.textRegions.count)")
            print("   🔲 UI elements: \(result.uiElements.count)")
            print("   📐 Layout type: \(result.layoutAnalysis.layoutType.rawValue)")
            print("   ⚡ Analysis time: \(String(format: "%.2f", result.analysisTime))s")
            print("   📊 Confidence: \(String(format: "%.1f", result.overallConfidence * 100))%")
            
            // Store the result for potential API calls to Python backend
            self.visionAnalysisResult = result
        } else {
            print("❌ Apple Vision analysis failed")
        }
        
        return result
    }
    
    // MARK: - Python Backend Integration
    
    func sendVisionAnalysisToBackend(question: String, userID: String = "default", chatID: String? = nil) async -> String? {
        return await sendVisionAnalysisToBackend(question: question, userID: userID, chatID: chatID, streaming: false)
    }
    
    // MARK: - Hybrid Analysis (Apple Vision + MLX-VLM + Main LLM)
    
    func performDualContextAnalysis(question: String, userID: String = "default", chatID: String? = nil) async -> String? {
        guard let visionResult = self.visionAnalysisResult,
              let capturedImage = self.lastCapturedImage else {
            print("⚠️ No vision analysis or captured image available")
            return nil
        }
        
        print("🔄 Starting DUAL-CONTEXT analysis pipeline...")
        print("   1️⃣ PRIMARY: Using macOS Apple Vision OCR results")
        print("   2️⃣ SECONDARY: Requesting MLX-VLM visual analysis")
        print("   3️⃣ INTEGRATION: Combining contexts for main LLM")
        
        // STEP 1: Get primary OCR from Apple Vision (already done)
        let primaryOCR = visionResult.extractedText
        print("✅ PRIMARY OCR extracted: \(primaryOCR.count) characters")
        
        // STEP 2: Get secondary visual analysis from MLX-VLM backend
        let secondaryAnalysis = await performMLXVLMAnalysis(
            question: question, 
            primaryOCR: primaryOCR, 
            image: capturedImage
        )
        
        // STEP 3: Combine both contexts for main LLM
        let combinedAnalysis = await processCombinedContext(
            question: question,
            primaryOCR: primaryOCR,
            secondaryVLM: secondaryAnalysis,
            userID: userID,
            chatID: chatID
        )
        
        return combinedAnalysis
    }
    
    private func performMLXVLMAnalysis(question: String, primaryOCR: String, image: NSImage) async -> String {
        print("🔍 Performing SECONDARY MLX-VLM analysis...")
        
        guard let imageBase64 = imageToBase64(image) else {
            print("❌ Failed to convert image to base64")
            return ""
        }
        
        do {
            let serverURL = serverConfig.currentServerURL
            guard let url = URL(string: "\(serverURL)/mlx_vlm_analysis") else {
                print("❌ Invalid MLX-VLM endpoint URL")
                return ""
            }
            
            let requestBody: [String: Any] = [
                "image_base64": imageBase64,
                "question": question,
                "swift_ocr_text": primaryOCR,
                "user_id": "default"
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 30.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 MLX-VLM response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let success = responseDict["success"] as? Bool {
                        
                        if success {
                            let vlmAnalysis = responseDict["vlm_analysis"] as? String ?? ""
                            let modelUsed = responseDict["model_used"] as? String ?? "unknown"
                            
                            print("✅ SECONDARY MLX-VLM analysis completed using: \(modelUsed)")
                            print("   📊 VLM analysis length: \(vlmAnalysis.count) characters")
                            
                            return vlmAnalysis
                        } else {
                            let error = responseDict["error"] as? String ?? "Unknown error"
                            print("⚠️ MLX-VLM analysis failed: \(error)")
                            return ""
                        }
                    }
                }
            }
        } catch {
            print("❌ MLX-VLM communication failed: \(error)")
        }
        
        return ""
    }
    
    private func processCombinedContext(question: String, primaryOCR: String, secondaryVLM: String, userID: String, chatID: String?) async -> String? {
        print("🔗 Processing COMBINED CONTEXT for main LLM...")
        
        do {
            let serverURL = serverConfig.currentServerURL
            guard let url = URL(string: "\(serverURL)/analyze_screen_dual_context") else {
                print("❌ Invalid dual context endpoint URL")
                return nil
            }
            
            let requestBody: [String: Any] = [
                "question": question,
                "primary_ocr": primaryOCR,
                "secondary_vlm": secondaryVLM,
                "user_id": userID,
                "chat_id": chatID ?? UUID().uuidString,
                "analysis_type": "dual_context_macos_mlx"
            ]
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 60.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Dual context response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answer = responseDict["answer"] as? String {
                        
                        print("✅ DUAL-CONTEXT analysis completed successfully")
                        print("   📝 Combined analysis length: \(answer.count) characters")
                        
                        return answer
                    }
                }
            }
        } catch {
            print("❌ Dual context communication failed: \(error)")
        }
        
        return nil
    }
    
    func performHybridAnalysis(question: String, userID: String = "default", chatID: String? = nil) async -> String? {
        // Legacy method - redirects to new dual context analysis
        return await performDualContextAnalysis(question: question, userID: userID, chatID: chatID)
    }
    
    private func sendImageToMLXVLM(image: NSImage, question: String) async -> [String: Any] {
        guard let imageBase64 = imageToBase64(image) else {
            print("❌ Failed to convert image to base64")
            return ["error": "Failed to process image"]
        }
        
        let requestBody: [String: Any] = [
            "image_base64": imageBase64,
            "question": question,
            "analysis_type": "detailed_visual_analysis"
        ]
        
        do {
            let serverURL = serverConfig.currentServerURL
            guard let url = URL(string: "\(serverURL)/analyze_image_mlx_vlm") else {
                print("❌ Invalid MLX-VLM URL")
                return ["error": "Invalid URL"]
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 60.0 // Longer timeout for vision models
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 MLX-VLM response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("✅ MLX-VLM analysis completed")
                        return responseDict
                    }
                } else {
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ MLX-VLM error (\(httpResponse.statusCode)): \(errorMsg)")
                }
            }
        } catch {
            print("❌ Failed to communicate with MLX-VLM: \(error)")
        }
        
        return ["error": "MLX-VLM analysis failed", "fallback": "Using Apple Vision only"]
    }
    
    private func sendHybridContextToLLM(
        question: String,
        appleVisionContext: [String: Any],
        mlxVlmContext: [String: Any],
        userID: String,
        chatID: String?
    ) async -> String? {
        
        let requestBody: [String: Any] = [
            "question": question,
            "user_id": userID,
            "chat_id": chatID ?? UUID().uuidString,
            "apple_vision_context": appleVisionContext,
            "mlx_vlm_context": mlxVlmContext,
            "processing_method": "hybrid_apple_vision_mlx_vlm"
        ]
        
        do {
            let serverURL = serverConfig.currentServerURL
            guard let url = URL(string: "\(serverURL)/analyze_screen_hybrid") else {
                print("❌ Invalid hybrid analysis URL")
                return nil
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 60.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Hybrid analysis response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answer = responseDict["answer"] as? String {
                        
                        print("✅ Hybrid analysis completed successfully")
                        return answer
                    }
                } else {
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Hybrid analysis error (\(httpResponse.statusCode)): \(errorMsg)")
                }
            }
        } catch {
            print("❌ Failed to communicate with hybrid analysis endpoint: \(error)")
        }
        
        return nil
    }
    
    func streamVisionAnalysisFromBackend(question: String, userID: String = "default", chatID: String? = nil, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void) async {
        await streamVisionAnalysisToBackend(question: question, userID: userID, chatID: chatID, onChunk: onChunk, onComplete: onComplete)
    }
    
    private func sendVisionAnalysisToBackend(question: String, userID: String = "default", chatID: String? = nil, streaming: Bool) async -> String? {
        guard let visionResult = self.visionAnalysisResult else {
            print("⚠️ No vision analysis result available")
            return nil
        }
        
        print("🔄 Sending structured vision data to Python backend...")
        
        // Convert vision result to structured JSON for backend
        let visionData = visionResult.toJSONDictionary()
        
        let requestBody: [String: Any] = [
            "question": question,
            "user_id": userID,
            "chat_id": chatID ?? UUID().uuidString,
            "vision_data": visionData,
            "processing_method": "swift_vision_structured"
        ]
        
        do {
            let serverURL = serverConfig.currentServerURL
            let endpoint = streaming ? "/analyze_screen_structured_stream" : "/analyze_screen_structured"
            guard let url = URL(string: "\(serverURL)\(endpoint)") else {
                print("❌ Invalid backend URL")
                return nil
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 30.0
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Backend response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    if let responseDict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let answer = responseDict["answer"] as? String {
                        
                        print("✅ Received structured analysis from backend")
                        return answer
                    }
                } else {
                    let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("❌ Backend error (\(httpResponse.statusCode)): \(errorMsg)")
                }
            }
        } catch {
            print("❌ Failed to communicate with backend: \(error)")
        }
        
        return nil
    }
    
    private func streamVisionAnalysisToBackend(question: String, userID: String = "default", chatID: String? = nil, onChunk: @escaping (String) -> Void, onComplete: @escaping () -> Void) async {
        guard let visionResult = self.visionAnalysisResult else {
            print("⚠️ No vision analysis result available")
            onComplete()
            return
        }
        
        print("🌊 Streaming structured vision data to Python backend...")
        
        // Convert vision result to structured JSON for backend
        let visionData = visionResult.toJSONDictionary()
        
        let requestBody: [String: Any] = [
            "question": question,
            "user_id": userID,
            "chat_id": chatID ?? UUID().uuidString,
            "vision_data": visionData,
            "processing_method": "swift_vision_structured"
        ]
        
        do {
            let serverURL = serverConfig.currentServerURL
            guard let url = URL(string: "\(serverURL)/analyze_screen_structured_stream") else {
                print("❌ Invalid backend URL")
                onComplete()
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            request.timeoutInterval = 60.0 // Longer timeout for streaming
            
            let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("📡 Streaming response status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    print("✅ Starting stream processing...")
                    
                    var buffer = ""
                    for try await byte in asyncBytes {
                        // UnicodeScalar(byte) doesn't return Optional, so we can use it directly
                        let character = Character(UnicodeScalar(Int(byte)) ?? UnicodeScalar(32)!) // fallback to space
                        buffer.append(character)
                        
                        // Process complete lines
                        while let lineEnd = buffer.firstIndex(of: "\n") {
                            let line = String(buffer[..<lineEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                            buffer.removeSubrange(...lineEnd)
                            
                            // Parse SSE format
                            if line.hasPrefix("data: ") {
                                let dataString = String(line.dropFirst(6))
                                
                                // Parse JSON
                                if let data = dataString.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                                   let type = json["type"] as? String,
                                   let content = json["content"] as? String {
                                    
                                    switch type {
                                    case "header", "chunk", "footer":
                                        onChunk(content)
                                    case "complete":
                                        print("✅ Streaming completed successfully")
                                        onComplete()
                                        return
                                    case "error":
                                        print("❌ Streaming error: \(content)")
                                        onChunk("Error: \(content)")
                                        onComplete()
                                        return
                                    default:
                                        continue
                                    }
                                }
                            }
                        }
                    }
                    
                    onComplete()
                } else {
                    print("❌ Streaming failed with status: \(httpResponse.statusCode)")
                    onComplete()
                }
            }
        } catch {
            print("❌ Failed to stream from backend: \(error)")
            onComplete()
        }
    }
    
    // MARK: - Text Extraction using Vision (Fallback)
    
    private func extractTextFromImage(_ cgImage: CGImage) async -> String {
        // Perform comprehensive image analysis including text, objects, and layout
        let textContent = await extractTextWithVision(cgImage)
        let imageAnalysis = await analyzeImageContent(cgImage)
        
        var combinedContent = textContent
        if !imageAnalysis.isEmpty {
            combinedContent += "\n\nIMAGE ANALYSIS:\n\(imageAnalysis)"
        }
        
        return combinedContent
    }
    
    private func extractTextWithVision(_ cgImage: CGImage) async -> String {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("❌ Text recognition error: \(error)")
                    continuation.resume(returning: "")
                    return
                }
                
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: "")
                    return
                }
                
                // Enhanced text extraction with spatial information
                let textElements = observations.compactMap { observation -> String? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let confidence = candidate.confidence
                    let text = candidate.string
                    
                    // Include confidence and spatial info for important text
                    if confidence > 0.8 {
                        return text
                    } else if confidence > 0.5 {
                        return "\(text) [low confidence]"
                    }
                    return nil
                }
                
                continuation.resume(returning: textElements.joined(separator: "\n"))
            }
            
            // Configure for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"] // Can be expanded
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform text recognition: \(error)")
                continuation.resume(returning: "")
            }
        }
    }
    
    private func analyzeImageContent(_ cgImage: CGImage) async -> String {
        var analysisResults: [String] = []
        
        // Object detection
        if let objects = await detectObjects(cgImage) {
            analysisResults.append("Objects detected: \(objects)")
        }
        
        // Rectangle detection (UI elements, buttons, etc.)
        if let rectangles = await detectRectangles(cgImage) {
            analysisResults.append("UI elements detected: \(rectangles)")
        }
        
        // Face detection
        if let faces = await detectFaces(cgImage) {
            analysisResults.append("Faces detected: \(faces)")
        }
        
        // Barcode/QR code detection
        if let barcodes = await detectBarcodes(cgImage) {
            analysisResults.append("Barcodes/QR codes: \(barcodes)")
        }
        
        return analysisResults.joined(separator: "\n")
    }
    
    private func detectObjects(_ cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                if let error = error {
                    print("❌ Object detection error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let topObjects = observations.prefix(5).compactMap { observation in
                    observation.confidence > 0.3 ? "\(observation.identifier) (\(Int(observation.confidence * 100))%)" : nil
                }
                
                continuation.resume(returning: topObjects.isEmpty ? nil : topObjects.joined(separator: ", "))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform object detection: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func detectRectangles(_ cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    print("❌ Rectangle detection error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let rectangleInfo = observations.prefix(10).enumerated().map { index, rect in
                    "Rectangle \(index + 1) (confidence: \(Int(rect.confidence * 100))%)"
                }
                
                continuation.resume(returning: rectangleInfo.isEmpty ? nil : rectangleInfo.joined(separator: ", "))
            }
            
            request.maximumObservations = 10
            request.minimumConfidence = 0.6
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform rectangle detection: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func detectFaces(_ cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, error in
                if let error = error {
                    print("❌ Face detection error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNFaceObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                if observations.count > 0 {
                    continuation.resume(returning: "\(observations.count) face(s)")
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform face detection: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    private func detectBarcodes(_ cgImage: CGImage) async -> String? {
        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error = error {
                    print("❌ Barcode detection error: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: nil)
                    return
                }
                
                let barcodeInfo = observations.compactMap { barcode in
                    if let payloadString = barcode.payloadStringValue {
                        return "\(barcode.symbology.rawValue): \(payloadString)"
                    }
                    return nil
                }
                
                continuation.resume(returning: barcodeInfo.isEmpty ? nil : barcodeInfo.joined(separator: ", "))
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform barcode detection: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Utility Functions
    
    func imageToBase64(_ image: NSImage) -> String? {
        // Method 1: Try direct CGImage conversion (more reliable for screen captures)
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            bitmapRep.size = image.size
            
            // Force sRGB color space to avoid Preview app color space conflicts
            let sRGBColorSpace = NSColorSpace.sRGB
            let convertedRep = bitmapRep.converting(to: sRGBColorSpace, renderingIntent: .default)
            if let pngData = convertedRep?.representation(using: .png, properties: [:]) {
                print("✅ Image converted using direct CGImage method with sRGB color space")
                return pngData.base64EncodedString()
            }
            
            // Fallback without color space conversion
            if let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                print("✅ Image converted using direct CGImage method")
                return pngData.base64EncodedString()
            }
        }
        
        // Method 2: Original TIFF-based method (fallback)
        guard let tiffData = image.tiffRepresentation else {
            print("❌ Failed to get TIFF representation")
            return nil
        }
        
        guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            print("❌ Failed to create bitmap rep from TIFF data")
            return nil
        }
        
        // Debug color space info
        let colorSpace = bitmapRep.colorSpace
        print("🎨 Original color space: \(colorSpace.localizedName ?? "Unknown")")
        
        // Convert to sRGB if it's not already
        let sRGBColorSpace = NSColorSpace.sRGB
        if colorSpace != sRGBColorSpace {
            print("🔄 Converting from \(colorSpace.localizedName ?? "Unknown") to sRGB")
            if let convertedRep = bitmapRep.converting(to: sRGBColorSpace, renderingIntent: .default) {
                if let pngData = convertedRep.representation(using: .png, properties: [:]) {
                    print("✅ Image converted with color space correction")
                    return pngData.base64EncodedString()
                }
            }
        }
        
        // Final fallback - original method
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            print("❌ Failed to create PNG data")
            return nil
        }
        
        print("✅ Image converted using TIFF fallback method")
        return pngData.base64EncodedString()
    }
    
    func getWindowInfo(for window: SCWindow) -> WindowInfo {
        return WindowInfo(
            title: window.title ?? "Unknown",
            appName: window.owningApplication?.applicationName ?? "Unknown",
            bounds: window.frame
        )
    }

}
