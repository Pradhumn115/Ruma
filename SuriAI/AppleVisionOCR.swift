//
//  AppleVisionOCR.swift
//  SuriAI - Enhanced Apple Vision OCR Integration
//
//  Created by Claude on 01/07/25.
//

import SwiftUI
import Vision
import CoreImage
import AppKit
import UniformTypeIdentifiers
import VisionKit

// MARK: - Data Structures

// Visual Look Up Results
@available(macOS 13.0, *)
struct VisualLookUpResult {
    let classifications: [VNClassificationObservation]
    let detectedObjects: [VNRecognizedObjectObservation]
    let textObservations: [VNRecognizedTextObservation]
    let confidence: Float
    let processingTime: TimeInterval
}

struct VisualLookUpInsight {
    let type: LookUpType
    let content: String
    let confidence: Float
    let boundingBox: CGRect?
}

enum LookUpType: String, CaseIterable {
    case object = "object"
    case landmark = "landmark"
    case plant = "plant"
    case animal = "animal"
    case food = "food"
    case document = "document"
    case qrcode = "qrcode"
    case barcode = "barcode"
    case artwork = "artwork"
    case brand = "brand"
}

struct VisionTextRegion {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
    let textType: TextType
    let fontSize: CGFloat?
    let characteristics: TextCharacteristics
}

struct TextCharacteristics {
    let isBold: Bool
    let isItalic: Bool
    let isUppercase: Bool
    let isNumeric: Bool
    let isLink: Bool
    let backgroundColor: NSColor?
    let textColor: NSColor?
}

enum TextType: String, CaseIterable {
    case heading = "heading"
    case button = "button"
    case label = "label"
    case menuItem = "menu_item"
    case bodyText = "body_text"
    case caption = "caption"
    case code = "code"
    case url = "url"
    case unknown = "unknown"
}

struct UIElementDetection {
    let elementType: UIElementType
    let boundingBox: CGRect
    let confidence: Float
    let properties: [String: Any]
}

enum UIElementType: String, CaseIterable {
    case button = "button"
    case textField = "text_field"
    case label = "label"
    case image = "image"
    case icon = "icon"
    case menu = "menu"
    case window = "window"
    case dialog = "dialog"
    case chart = "chart"
    case table = "table"
    case list = "list"
}

struct LayoutAnalysis {
    let layoutType: LayoutType
    let regions: [LayoutRegion]
    let readingOrder: [Int] // Indices of text regions in reading order
    let dominantLanguage: String
    let textDensity: Float
}

enum LayoutType: String, CaseIterable {
    case document = "document"
    case webpage = "webpage"
    case application = "application"
    case dialog = "dialog"
    case menu = "menu"
    case dashboard = "dashboard"
    case form = "form"
    case terminal = "terminal"
    case code = "code"
    case mixed = "mixed"
}

struct LayoutRegion {
    let type: RegionType
    let boundingBox: CGRect
    let textRegions: [Int] // Indices of text regions in this layout region
}

enum RegionType: String, CaseIterable {
    case header = "header"
    case footer = "footer"
    case sidebar = "sidebar"
    case mainContent = "main_content"
    case navigation = "navigation"
    case toolbar = "toolbar"
    case statusBar = "status_bar"
}

struct VisionAnalysisResult {
    let textRegions: [VisionTextRegion]
    let uiElements: [UIElementDetection]
    let layoutAnalysis: LayoutAnalysis
    let overallConfidence: Float
    let analysisTime: TimeInterval
    let imageSize: CGSize
    let extractedText: String // Organized text for sending to Python
    let visualLookUpInsights: [VisualLookUpInsight] // Apple Visual Look Up results
    let metadata: [String: Any]
}

// MARK: - Apple Vision OCR Engine

@available(macOS 11.0, *)
class AppleVisionOCR: ObservableObject {
    
    @Published var isProcessing = false
    @Published var lastError: String?
    
    private let textRecognitionQueue = DispatchQueue(label: "vision.textRecognition", qos: .userInitiated)
    
    // MARK: - Main Analysis Method
    
    func analyzeImage(_ image: NSImage) async -> VisionAnalysisResult? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            await MainActor.run { self.lastError = "Failed to convert NSImage to CGImage" }
            return nil
        }
        
        let startTime = Date()
        
        await MainActor.run { self.isProcessing = true }
        defer { Task { await MainActor.run { self.isProcessing = false } } }
        
        do {
            // Perform parallel analysis including Visual Look Up
            async let textRegions = extractTextRegions(from: cgImage)
            async let uiElements = detectUIElements(from: cgImage)
            async let visualLookUpInsights = performVisualLookUp(from: cgImage)
            
            let extractedTextRegions = await textRegions
            let detectedUIElements = await uiElements
            let lookUpResults = await visualLookUpInsights
            
            // Perform layout analysis
            let layoutAnalysis = analyzeLayout(
                textRegions: extractedTextRegions,
                uiElements: detectedUIElements,
                imageSize: image.size
            )
            
            // Calculate overall confidence
            let overallConfidence = calculateOverallConfidence(
                textRegions: extractedTextRegions,
                uiElements: detectedUIElements
            )
            
            // Organize text for Python processing
            let organizedText = organizeTextForProcessing(
                textRegions: extractedTextRegions,
                layoutAnalysis: layoutAnalysis
            )
            
            let analysisTime = Date().timeIntervalSince(startTime)
            
            return VisionAnalysisResult(
                textRegions: extractedTextRegions,
                uiElements: detectedUIElements,
                layoutAnalysis: layoutAnalysis,
                overallConfidence: overallConfidence,
                analysisTime: analysisTime,
                imageSize: image.size,
                extractedText: organizedText,
                visualLookUpInsights: lookUpResults,
                metadata: buildMetadata(
                    textRegions: extractedTextRegions,
                    uiElements: detectedUIElements,
                    layoutAnalysis: layoutAnalysis,
                    visualLookUpInsights: lookUpResults
                )
            )
            
        } catch {
            await MainActor.run { self.lastError = "Vision analysis failed: \(error.localizedDescription)" }
            return nil
        }
    }
    
    // MARK: - Text Recognition
    
    private func extractTextRegions(from cgImage: CGImage) async -> [VisionTextRegion] {
        return await withCheckedContinuation { continuation in
            textRecognitionQueue.async {
                var textRegions: [VisionTextRegion] = []
                
                let request = VNRecognizeTextRequest { request, error in
                    if let error = error {
                        print("❌ Text recognition error: \(error)")
                        continuation.resume(returning: [])
                        return
                    }
                    
                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: [])
                        return
                    }
                    
                    for observation in observations {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        
                        let text = candidate.string
                        let confidence = candidate.confidence
                        let boundingBox = observation.boundingBox
                        
                        // Convert normalized coordinates to image coordinates
                        let imageRect = VNImageRectForNormalizedRect(
                            boundingBox,
                            Int(cgImage.width),
                            Int(cgImage.height)
                        )
                        
                        // Analyze text characteristics
                        let characteristics = self.analyzeTextCharacteristics(
                            text: text,
                            observation: observation,
                            cgImage: cgImage
                        )
                        
                        // Classify text type
                        let textType = self.classifyTextType(
                            text: text,
                            characteristics: characteristics,
                            boundingBox: imageRect
                        )
                        
                        let region = VisionTextRegion(
                            text: text,
                            confidence: confidence,
                            boundingBox: imageRect,
                            textType: textType,
                            fontSize: self.estimateFontSize(boundingBox: imageRect),
                            characteristics: characteristics
                        )
                        
                        textRegions.append(region)
                    }
                    
                    continuation.resume(returning: textRegions)
                }
                
                // Configure for maximum accuracy
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = ["en-US", "en-GB"] // Can be expanded
                
                // Enable additional features if available
                if #available(macOS 13.0, *) {
                    request.automaticallyDetectsLanguage = true
                }
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([request])
                } catch {
                    print("❌ Failed to perform text recognition: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - UI Element Detection
    
    private func detectUIElements(from cgImage: CGImage) async -> [UIElementDetection] {
        return await withCheckedContinuation { continuation in
            textRecognitionQueue.async {
                var uiElements: [UIElementDetection] = []
                
                // Rectangle detection for UI elements
                let rectangleRequest = VNDetectRectanglesRequest { request, error in
                    guard let observations = request.results as? [VNRectangleObservation] else { return }
                    
                    for observation in observations {
                        let boundingBox = VNImageRectForNormalizedRect(
                            observation.boundingBox,
                            Int(cgImage.width),
                            Int(cgImage.height)
                        )
                        
                        let elementType = self.classifyUIElement(
                            boundingBox: boundingBox,
                            confidence: observation.confidence
                        )
                        
                        let element = UIElementDetection(
                            elementType: elementType,
                            boundingBox: boundingBox,
                            confidence: observation.confidence,
                            properties: [
                                "aspectRatio": boundingBox.width / boundingBox.height,
                                "area": boundingBox.width * boundingBox.height
                            ]
                        )
                        
                        uiElements.append(element)
                    }
                }
                
                rectangleRequest.maximumObservations = 50
                rectangleRequest.minimumConfidence = 0.6
                rectangleRequest.minimumAspectRatio = 0.1
                rectangleRequest.maximumAspectRatio = 10.0
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                
                do {
                    try handler.perform([rectangleRequest])
                    continuation.resume(returning: uiElements)
                } catch {
                    print("❌ Failed to perform UI element detection: \(error)")
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    // MARK: - Text Analysis Helpers
    
    private func analyzeTextCharacteristics(text: String, observation: VNRecognizedTextObservation, cgImage: CGImage) -> TextCharacteristics {
        // Analyze text characteristics
        let isBold = estimateIsBold(observation: observation)
        let isItalic = estimateIsItalic(observation: observation)
        let isUppercase = text.uppercased() == text && text.count > 1
        let isNumeric = text.allSatisfy { $0.isNumber || $0.isPunctuation }
        let isLink = detectLink(text: text)
        
        return TextCharacteristics(
            isBold: isBold,
            isItalic: isItalic,
            isUppercase: isUppercase,
            isNumeric: isNumeric,
            isLink: isLink,
            backgroundColor: nil, // Could be extracted with more complex analysis
            textColor: nil
        )
    }
    
    private func classifyTextType(text: String, characteristics: TextCharacteristics, boundingBox: CGRect) -> TextType {
        let textLower = text.lowercased()
        
        // URL detection
        if characteristics.isLink || textLower.contains("http") || textLower.contains("www.") {
            return .url
        }
        
        // Code detection
        if textLower.contains("func") || textLower.contains("var") || textLower.contains("let") ||
           textLower.contains("{") || textLower.contains("}") || textLower.contains("()") {
            return .code
        }
        
        // Button detection
        if (text.count < 20 && (textLower.contains("click") || textLower.contains("button") ||
                               textLower.contains("submit") || textLower.contains("cancel") ||
                               textLower.contains("ok") || textLower.contains("apply"))) {
            return .button
        }
        
        // Menu item detection
        if text.count < 30 && (textLower.contains("file") || textLower.contains("edit") ||
                              textLower.contains("view") || textLower.contains("help") ||
                              textLower.contains("window") || textLower.contains("preferences")) {
            return .menuItem
        }
        
        // Heading detection (large, bold, or uppercase)
        if characteristics.isBold || characteristics.isUppercase || boundingBox.height > 20 {
            return .heading
        }
        
        // Label detection (ends with colon)
        if text.hasSuffix(":") && text.count < 50 {
            return .label
        }
        
        // Caption detection (small text)
        if boundingBox.height < 12 && text.count < 100 {
            return .caption
        }
        
        return .bodyText
    }
    
    private func estimateIsBold(observation: VNRecognizedTextObservation) -> Bool {
        // This is a simplified estimation - in practice, you might analyze stroke width
        return observation.topCandidates(1).first?.confidence ?? 0 > 0.9
    }
    
    private func estimateIsItalic(observation: VNRecognizedTextObservation) -> Bool {
        // Simplified estimation - could analyze character slant
        return false
    }
    
    private func detectLink(text: String) -> Bool {
        let linkPatterns = [
            "http://", "https://", "www.", ".com", ".org", ".net", ".edu",
            "ftp://", "mailto:", ".gov", ".io", ".co"
        ]
        
        let textLower = text.lowercased()
        return linkPatterns.contains { textLower.contains($0) }
    }
    
    private func estimateFontSize(boundingBox: CGRect) -> CGFloat {
        // Rough estimation based on height
        return max(8.0, min(72.0, boundingBox.height * 0.8))
    }
    
    // MARK: - UI Element Classification
    
    private func classifyUIElement(boundingBox: CGRect, confidence: Float) -> UIElementType {
        let aspectRatio = boundingBox.width / boundingBox.height
        let area = boundingBox.width * boundingBox.height
        
        // Button-like elements (roughly rectangular, medium size)
        if aspectRatio > 1.5 && aspectRatio < 8.0 && area > 500 && area < 50000 {
            return .button
        }
        
        // Text field-like elements (wide and short)
        if aspectRatio > 3.0 && boundingBox.height < 40 && area > 1000 {
            return .textField
        }
        
        // Icon-like elements (small and square-ish)
        if aspectRatio > 0.5 && aspectRatio < 2.0 && area < 2000 {
            return .icon
        }
        
        // Large rectangular regions might be windows or dialogs
        if area > 50000 {
            return aspectRatio > 1.2 ? .window : .dialog
        }
        
        return .label
    }
    
    // MARK: - Layout Analysis
    
    private func analyzeLayout(textRegions: [VisionTextRegion], uiElements: [UIElementDetection], imageSize: CGSize) -> LayoutAnalysis {
        
        // Determine layout type
        let layoutType = determineLayoutType(textRegions: textRegions, uiElements: uiElements, imageSize: imageSize)
        
        // Identify layout regions
        let regions = identifyLayoutRegions(textRegions: textRegions, uiElements: uiElements, imageSize: imageSize)
        
        // Determine reading order
        let readingOrder = calculateReadingOrder(textRegions: textRegions)
        
        // Analyze language and text density
        let dominantLanguage = "en" // Could be enhanced with language detection
        let textDensity = calculateTextDensity(textRegions: textRegions, imageSize: imageSize)
        
        return LayoutAnalysis(
            layoutType: layoutType,
            regions: regions,
            readingOrder: readingOrder,
            dominantLanguage: dominantLanguage,
            textDensity: textDensity
        )
    }
    
    private func determineLayoutType(textRegions: [VisionTextRegion], uiElements: [UIElementDetection], imageSize: CGSize) -> LayoutType {
        let buttons = uiElements.filter { $0.elementType == .button }
        let textFields = uiElements.filter { $0.elementType == .textField }
        let headings = textRegions.filter { $0.textType == .heading }
        let menuItems = textRegions.filter { $0.textType == .menuItem }
        let codeText = textRegions.filter { $0.textType == .code }
        
        // Code/terminal detection
        if codeText.count > textRegions.count / 3 {
            return .code
        }
        
        // Menu detection
        if menuItems.count > 3 && buttons.count < 3 {
            return .menu
        }
        
        // Form detection
        if textFields.count > 2 || (buttons.count > 1 && textRegions.filter { $0.textType == .label }.count > 2) {
            return .form
        }
        
        // Dialog detection
        if imageSize.width < 600 && imageSize.height < 400 && buttons.count > 0 {
            return .dialog
        }
        
        // Dashboard detection (lots of structured content)
        if headings.count > 2 && textRegions.count > 20 {
            return .dashboard
        }
        
        // Web page detection (mixed content types)
        if textRegions.filter({ $0.textType == .url }).count > 0 && headings.count > 1 {
            return .webpage
        }
        
        // Document detection (mostly body text)
        if textRegions.filter({ $0.textType == .bodyText }).count > textRegions.count / 2 {
            return .document
        }
        
        return .application
    }
    
    private func identifyLayoutRegions(textRegions: [VisionTextRegion], uiElements: [UIElementDetection], imageSize: CGSize) -> [LayoutRegion] {
        var regions: [LayoutRegion] = []
        
        let imageHeight = imageSize.height
        let imageWidth = imageSize.width
        
        // Header region (top 15% of screen)
        let headerBounds = CGRect(x: 0, y: imageHeight * 0.85, width: imageWidth, height: imageHeight * 0.15)
        let headerTextIndices = textRegions.enumerated().compactMap { index, region in
            headerBounds.intersects(region.boundingBox) ? index : nil
        }
        if !headerTextIndices.isEmpty {
            regions.append(LayoutRegion(type: .header, boundingBox: headerBounds, textRegions: headerTextIndices))
        }
        
        // Footer region (bottom 10% of screen)
        let footerBounds = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight * 0.1)
        let footerTextIndices = textRegions.enumerated().compactMap { index, region in
            footerBounds.intersects(region.boundingBox) ? index : nil
        }
        if !footerTextIndices.isEmpty {
            regions.append(LayoutRegion(type: .footer, boundingBox: footerBounds, textRegions: footerTextIndices))
        }
        
        // Sidebar region (left 20% of screen if text density is low in center)
        let sidebarBounds = CGRect(x: 0, y: imageHeight * 0.1, width: imageWidth * 0.2, height: imageHeight * 0.75)
        let sidebarTextIndices = textRegions.enumerated().compactMap { index, region in
            sidebarBounds.intersects(region.boundingBox) ? index : nil
        }
        if sidebarTextIndices.count > 2 {
            regions.append(LayoutRegion(type: .sidebar, boundingBox: sidebarBounds, textRegions: sidebarTextIndices))
        }
        
        // Main content region (remaining center area)
        let mainBounds = CGRect(
            x: regions.contains(where: { $0.type == .sidebar }) ? imageWidth * 0.2 : 0,
            y: imageHeight * 0.1,
            width: imageWidth * (regions.contains(where: { $0.type == .sidebar }) ? 0.8 : 1.0),
            height: imageHeight * 0.75
        )
        let mainTextIndices = textRegions.enumerated().compactMap { index, region in
            mainBounds.intersects(region.boundingBox) && !headerTextIndices.contains(index) && !footerTextIndices.contains(index) && !sidebarTextIndices.contains(index) ? index : nil
        }
        if !mainTextIndices.isEmpty {
            regions.append(LayoutRegion(type: .mainContent, boundingBox: mainBounds, textRegions: mainTextIndices))
        }
        
        return regions
    }
    
    private func calculateReadingOrder(textRegions: [VisionTextRegion]) -> [Int] {
        // Sort by Y position (top to bottom), then X position (left to right)
        return textRegions.enumerated().sorted { first, second in
            let firstY = first.element.boundingBox.maxY
            let secondY = second.element.boundingBox.maxY
            
            // If roughly on the same line (within 10 pixels), sort by X
            if abs(firstY - secondY) < 10 {
                return first.element.boundingBox.minX < second.element.boundingBox.minX
            }
            
            // Otherwise sort by Y (top to bottom)
            return firstY > secondY
        }.map { $0.offset }
    }
    
    private func calculateTextDensity(textRegions: [VisionTextRegion], imageSize: CGSize) -> Float {
        let totalTextArea = textRegions.reduce(0) { sum, region in
            sum + (region.boundingBox.width * region.boundingBox.height)
        }
        let imageArea = imageSize.width * imageSize.height
        return Float(totalTextArea / imageArea)
    }
    
    // MARK: - Result Processing
    
    private func calculateOverallConfidence(textRegions: [VisionTextRegion], uiElements: [UIElementDetection]) -> Float {
        guard !textRegions.isEmpty else { return 0.0 }
        
        let textConfidence = textRegions.reduce(0) { $0 + $1.confidence } / Float(textRegions.count)
        let uiConfidence = uiElements.isEmpty ? 1.0 : uiElements.reduce(0) { $0 + $1.confidence } / Float(uiElements.count)
        
        return (textConfidence * 0.7 + uiConfidence * 0.3)
    }
    
    private func organizeTextForProcessing(textRegions: [VisionTextRegion], layoutAnalysis: LayoutAnalysis) -> String {
        // Extract just the plain text content in reading order for better LLM understanding
        // Sort text regions by position (top to bottom, left to right)
        let sortedRegions = textRegions.sorted { region1, region2 in
            // Sort by Y position first (top to bottom), then by X position (left to right)
            if abs(region1.boundingBox.maxY - region2.boundingBox.maxY) < 20 {
                return region1.boundingBox.minX < region2.boundingBox.minX
            } else {
                return region1.boundingBox.maxY > region2.boundingBox.maxY
            }
        }
        
        // Extract all actual text content without analysis headers
        let textContent = sortedRegions.map { $0.text }.joined(separator: "\n")
        
        return textContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Apple Visual Look Up Integration
    
    @available(macOS 13.0, *)
    private func performVisualLookUp(from cgImage: CGImage) async -> [VisualLookUpInsight] {
        var insights: [VisualLookUpInsight] = []
        
        // Perform various Visual Look Up requests in parallel
        async let objectClassification = classifyObjects(cgImage)
        async let textClassification = classifyTextContent(cgImage)
        async let barcodeDetection = detectBarcodes(cgImage)
        async let documentDetection = detectDocuments(cgImage)
        
        // Collect all results
        let objects = await objectClassification
        let textInfo = await textClassification
        let barcodes = await barcodeDetection
        let documents = await documentDetection
        
        insights.append(contentsOf: objects)
        insights.append(contentsOf: textInfo)
        insights.append(contentsOf: barcodes)
        insights.append(contentsOf: documents)
        
        return insights
    }
    
    @available(macOS 13.0, *)
    private func classifyObjects(_ cgImage: CGImage) async -> [VisualLookUpInsight] {
        return await withCheckedContinuation { continuation in
            let request = VNClassifyImageRequest { request, error in
                guard let observations = request.results as? [VNClassificationObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let insights = observations.prefix(5).compactMap { observation -> VisualLookUpInsight? in
                    guard observation.confidence > 0.3 else { return nil }
                    
                    let type = self.categorizeLookUpType(from: observation.identifier)
                    return VisualLookUpInsight(
                        type: type,
                        content: "\(observation.identifier) (\(Int(observation.confidence * 100))% confidence)",
                        confidence: observation.confidence,
                        boundingBox: nil
                    )
                }
                
                continuation.resume(returning: insights)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    @available(macOS 13.0, *)
    private func classifyTextContent(_ cgImage: CGImage) async -> [VisualLookUpInsight] {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                var insights: [VisualLookUpInsight] = []
                
                for observation in observations.prefix(10) {
                    guard let topCandidate = observation.topCandidates(1).first,
                          topCandidate.confidence > 0.5 else { continue }
                    
                    let text = topCandidate.string
                    
                    // Check for specific patterns
                    if text.contains("@") && text.contains(".") {
                        insights.append(VisualLookUpInsight(
                            type: .document,
                            content: "Email address detected: \(text)",
                            confidence: topCandidate.confidence,
                            boundingBox: observation.boundingBox
                        ))
                    } else if text.range(of: #"https?://[^\s]+"#, options: .regularExpression) != nil {
                        insights.append(VisualLookUpInsight(
                            type: .document,
                            content: "URL detected: \(text)",
                            confidence: topCandidate.confidence,
                            boundingBox: observation.boundingBox
                        ))
                    } else if text.range(of: #"\$\d+\.?\d*"#, options: .regularExpression) != nil {
                        insights.append(VisualLookUpInsight(
                            type: .document,
                            content: "Price detected: \(text)",
                            confidence: topCandidate.confidence,
                            boundingBox: observation.boundingBox
                        ))
                    }
                }
                
                continuation.resume(returning: insights)
            }
            
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    @available(macOS 13.0, *)
    private func detectBarcodes(_ cgImage: CGImage) async -> [VisualLookUpInsight] {
        return await withCheckedContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let insights = observations.compactMap { barcode -> VisualLookUpInsight? in
                    guard let payload = barcode.payloadStringValue else { return nil }
                    
                    let type: LookUpType = barcode.symbology == .qr ? .qrcode : .barcode
                    return VisualLookUpInsight(
                        type: type,
                        content: "\(barcode.symbology.rawValue): \(payload)",
                        confidence: barcode.confidence,
                        boundingBox: barcode.boundingBox
                    )
                }
                
                continuation.resume(returning: insights)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    @available(macOS 13.0, *)
    private func detectDocuments(_ cgImage: CGImage) async -> [VisualLookUpInsight] {
        return await withCheckedContinuation { continuation in
            let request = VNDetectDocumentSegmentationRequest { request, error in
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let insights = observations.prefix(3).map { observation in
                    VisualLookUpInsight(
                        type: .document,
                        content: "Document or paper detected (confidence: \(Int(observation.confidence * 100))%)",
                        confidence: observation.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                
                continuation.resume(returning: insights)
            }
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: [])
            }
        }
    }
    
    private func categorizeLookUpType(from identifier: String) -> LookUpType {
        let id = identifier.lowercased()
        
        if id.contains("animal") || id.contains("dog") || id.contains("cat") || id.contains("bird") {
            return .animal
        } else if id.contains("plant") || id.contains("flower") || id.contains("tree") || id.contains("leaf") {
            return .plant
        } else if id.contains("food") || id.contains("fruit") || id.contains("vegetable") || id.contains("drink") {
            return .food
        } else if id.contains("landmark") || id.contains("monument") || id.contains("building") {
            return .landmark
        } else if id.contains("art") || id.contains("painting") || id.contains("sculpture") {
            return .artwork
        } else if id.contains("brand") || id.contains("logo") {
            return .brand
        } else {
            return .object
        }
    }
    
    private func buildMetadata(textRegions: [VisionTextRegion], uiElements: [UIElementDetection], layoutAnalysis: LayoutAnalysis, visualLookUpInsights: [VisualLookUpInsight]) -> [String: Any] {
        return [
            "total_text_regions": textRegions.count,
            "total_ui_elements": uiElements.count,
            "layout_type": layoutAnalysis.layoutType.rawValue,
            "text_density": layoutAnalysis.textDensity,
            "dominant_language": layoutAnalysis.dominantLanguage,
            "text_types": Dictionary(grouping: textRegions, by: { $0.textType.rawValue }).mapValues { $0.count },
            "ui_element_types": Dictionary(grouping: uiElements, by: { $0.elementType.rawValue }).mapValues { $0.count },
            "reading_order_length": layoutAnalysis.readingOrder.count,
            "layout_regions": layoutAnalysis.regions.map { $0.type.rawValue },
            "confidence_distribution": [
                "high": textRegions.filter { $0.confidence > 0.9 }.count,
                "medium": textRegions.filter { $0.confidence > 0.7 && $0.confidence <= 0.9 }.count,
                "low": textRegions.filter { $0.confidence <= 0.7 }.count
            ],
            "visual_lookup_insights": [
                "total_insights": visualLookUpInsights.count,
                "insights_by_type": Dictionary(grouping: visualLookUpInsights, by: { $0.type.rawValue }).mapValues { $0.count },
                "high_confidence_insights": visualLookUpInsights.filter { $0.confidence > 0.7 }.count,
                "detected_content": visualLookUpInsights.map { [
                    "type": $0.type.rawValue,
                    "content": $0.content,
                    "confidence": $0.confidence
                ] }
            ]
        ]
    }
}

// MARK: - Convenience Extensions

extension NSImage {
    func cgImage(forProposedRect proposedDestRect: UnsafeMutablePointer<NSRect>?, context: NSGraphicsContext?, hints: [NSImageRep.HintKey: Any]?) -> CGImage? {
        guard let imageData = self.tiffRepresentation,
              let source = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}

extension VisionAnalysisResult {
    func toJSONDictionary() -> [String: Any] {
        return [
            "text_regions": textRegions.map { region in
                [
                    "text": region.text,
                    "confidence": region.confidence,
                    "bounding_box": [
                        "x": region.boundingBox.minX,
                        "y": region.boundingBox.minY,
                        "width": region.boundingBox.width,
                        "height": region.boundingBox.height
                    ],
                    "text_type": region.textType.rawValue,
                    "font_size": region.fontSize ?? 0,
                    "characteristics": [
                        "is_bold": region.characteristics.isBold,
                        "is_italic": region.characteristics.isItalic,
                        "is_uppercase": region.characteristics.isUppercase,
                        "is_numeric": region.characteristics.isNumeric,
                        "is_link": region.characteristics.isLink
                    ]
                ]
            },
            "ui_elements": uiElements.map { element in
                [
                    "element_type": element.elementType.rawValue,
                    "confidence": element.confidence,
                    "bounding_box": [
                        "x": element.boundingBox.minX,
                        "y": element.boundingBox.minY,
                        "width": element.boundingBox.width,
                        "height": element.boundingBox.height
                    ],
                    "properties": element.properties
                ]
            },
            "layout_analysis": [
                "layout_type": layoutAnalysis.layoutType.rawValue,
                "text_density": layoutAnalysis.textDensity,
                "dominant_language": layoutAnalysis.dominantLanguage,
                "regions": layoutAnalysis.regions.map { region in
                    [
                        "type": region.type.rawValue,
                        "bounding_box": [
                            "x": region.boundingBox.minX,
                            "y": region.boundingBox.minY,
                            "width": region.boundingBox.width,
                            "height": region.boundingBox.height
                        ],
                        "text_regions": region.textRegions
                    ]
                },
                "reading_order": layoutAnalysis.readingOrder
            ],
            "visual_lookup_insights": visualLookUpInsights.map { insight in
                [
                    "type": insight.type.rawValue,
                    "content": insight.content,
                    "confidence": insight.confidence,
                    "bounding_box": insight.boundingBox != nil ? [
                        "x": insight.boundingBox!.minX,
                        "y": insight.boundingBox!.minY,
                        "width": insight.boundingBox!.width,
                        "height": insight.boundingBox!.height
                    ] : nil
                ]
            },
            "overall_confidence": overallConfidence,
            "analysis_time": analysisTime,
            "image_size": [
                "width": imageSize.width,
                "height": imageSize.height
            ],
            "extracted_text": extractedText,
            "metadata": metadata
        ]
    }
}