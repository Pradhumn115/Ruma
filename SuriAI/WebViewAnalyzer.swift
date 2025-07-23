//
//  WebViewAnalyzer.swift
//  SuriAI - Advanced Web Content Analysis
//
//  Created by Pradhumn Gupta on 30/06/25.
//

import SwiftUI
import WebKit
import JavaScriptCore
import Foundation

@MainActor
class WebViewAnalyzer: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isAnalyzing = false
    @Published var lastAnalysisResult: WebAnalysisResult?
    @Published var analysisError: String?
    
    // MARK: - Private Properties
    private var webView: WKWebView?
    private var analysisCompletion: ((WebAnalysisResult) -> Void)?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent() // Don't store any data
        
        // Allow JavaScript execution
        let userScript = WKUserScript(
            source: getContentExtractionScript(),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(userScript)
        
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
        webView?.isHidden = true // Background analysis
    }
    
    // MARK: - Public Analysis Methods
    
    func analyzeURL(_ url: String, question: String) async -> WebAnalysisResult {
        guard let webURL = URL(string: url.hasPrefix("http") ? url : "https://\(url)") else {
            return WebAnalysisResult.failure("Invalid URL: \(url)")
        }
        
        return await withCheckedContinuation { continuation in
            isAnalyzing = true
            analysisCompletion = { result in
                self.isAnalyzing = false
                self.lastAnalysisResult = result
                continuation.resume(returning: result)
            }
            
            // Load the URL and analyze
            webView?.load(URLRequest(url: webURL))
            
            // Set timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                if self.isAnalyzing {
                    self.isAnalyzing = false
                    let timeoutResult = WebAnalysisResult.failure("Analysis timeout after 10 seconds")
                    self.analysisCompletion?(timeoutResult)
                    self.analysisCompletion = nil
                }
            }
        }
    }
    
    func analyzeCurrentBrowserContent(appName: String, question: String) async -> WebAnalysisResult {
        // Get current browser URL
        guard let urlInfo = await getCurrentBrowserURL(appName: appName) else {
            return WebAnalysisResult.failure("Could not extract URL from \(appName)")
        }
        
        return await analyzeURL(urlInfo.url, question: question)
    }
    
    // MARK: - Browser URL Extraction
    
    private func getCurrentBrowserURL(appName: String) async -> (url: String, title: String)? {
        let script: String
        
        switch appName.lowercased() {
        case let app where app.contains("safari"):
            script = """
            tell application "Safari"
                if (count of windows) > 0 then
                    set currentTab to current tab of front window
                    return (URL of currentTab) & " ||| " & (name of currentTab)
                end if
                return ""
            end tell
            """
        case let app where app.contains("chrome"):
            script = """
            tell application "Google Chrome"
                if (count of windows) > 0 then
                    set currentTab to active tab of front window
                    return (URL of currentTab) & " ||| " & (title of currentTab)
                end if
                return ""
            end tell
            """
        case let app where app.contains("firefox"):
            script = """
            tell application "Firefox"
                if (count of windows) > 0 then
                    return "firefox-url-extraction-not-supported"
                end if
                return ""
            end tell
            """
        default:
            return nil
        }
        
        if let result = await executeAppleScript(script), !result.isEmpty {
            let components = result.components(separatedBy: " ||| ")
            if components.count >= 2 {
                return (url: components[0], title: components[1])
            } else if !result.isEmpty && !result.contains("not-supported") {
                return (url: result, title: "")
            }
        }
        
        return nil
    }
    
    private func executeAppleScript(_ script: String) async -> String? {
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
    
    // MARK: - JavaScript Content Extraction
    
    private func getContentExtractionScript() -> String {
        return """
        (function() {
            // Wait for page to be fully loaded
            if (document.readyState !== 'complete') {
                window.addEventListener('load', extractContent);
            } else {
                extractContent();
            }
            
            function extractContent() {
                try {
                    const analysis = {
                        url: window.location.href,
                        title: document.title,
                        metadata: extractMetadata(),
                        textContent: extractTextContent(),
                        structure: analyzeStructure(),
                        forms: analyzeForms(),
                        links: analyzeLinks(),
                        images: analyzeImages(),
                        scripts: analyzeScripts(),
                        styles: analyzeStyles(),
                        accessibility: analyzeAccessibility(),
                        performance: analyzePerformance(),
                        seo: analyzeSEO()
                    };
                    
                    // Send results back to Swift
                    window.webkit.messageHandlers.analysisResults?.postMessage(analysis);
                } catch (error) {
                    window.webkit.messageHandlers.analysisError?.postMessage({
                        error: error.message,
                        stack: error.stack
                    });
                }
            }
            
            function extractMetadata() {
                const meta = {};
                document.querySelectorAll('meta').forEach(tag => {
                    const name = tag.getAttribute('name') || tag.getAttribute('property') || tag.getAttribute('http-equiv');
                    const content = tag.getAttribute('content');
                    if (name && content) {
                        meta[name] = content;
                    }
                });
                return meta;
            }
            
            function extractTextContent() {
                // Remove script and style elements
                const elements = document.querySelectorAll('script, style');
                elements.forEach(el => el.remove());
                
                // Get main content areas
                const contentSelectors = [
                    'main', 'article', '[role="main"]', '.content', '#content',
                    '.post', '.article', '.entry-content', '.page-content'
                ];
                
                let mainContent = '';
                for (const selector of contentSelectors) {
                    const element = document.querySelector(selector);
                    if (element) {
                        mainContent = element.innerText || element.textContent || '';
                        break;
                    }
                }
                
                // Fallback to body if no main content found
                if (!mainContent) {
                    mainContent = document.body.innerText || document.body.textContent || '';
                }
                
                return {
                    main: mainContent.slice(0, 5000), // Limit size
                    headings: extractHeadings(),
                    paragraphs: extractParagraphs(),
                    lists: extractLists()
                };
            }
            
            function extractHeadings() {
                const headings = [];
                document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(heading => {
                    headings.push({
                        level: parseInt(heading.tagName.charAt(1)),
                        text: heading.innerText || heading.textContent || '',
                        id: heading.id
                    });
                });
                return headings;
            }
            
            function extractParagraphs() {
                const paragraphs = [];
                document.querySelectorAll('p').forEach((p, index) => {
                    const text = p.innerText || p.textContent || '';
                    if (text.length > 20) { // Only meaningful paragraphs
                        paragraphs.push({
                            index: index,
                            text: text.slice(0, 200) // Limit size
                        });
                    }
                });
                return paragraphs.slice(0, 10); // Limit count
            }
            
            function extractLists() {
                const lists = [];
                document.querySelectorAll('ul, ol').forEach((list, index) => {
                    const items = Array.from(list.querySelectorAll('li')).map(li => 
                        (li.innerText || li.textContent || '').slice(0, 100)
                    );
                    lists.push({
                        type: list.tagName.toLowerCase(),
                        items: items.slice(0, 5) // Limit items
                    });
                });
                return lists.slice(0, 5); // Limit lists
            }
            
            function analyzeStructure() {
                return {
                    hasHeader: !!document.querySelector('header, [role="banner"]'),
                    hasNav: !!document.querySelector('nav, [role="navigation"]'),
                    hasMain: !!document.querySelector('main, [role="main"]'),
                    hasAside: !!document.querySelector('aside, [role="complementary"]'),
                    hasFooter: !!document.querySelector('footer, [role="contentinfo"]'),
                    sectionsCount: document.querySelectorAll('section').length,
                    articlesCount: document.querySelectorAll('article').length,
                    divsCount: document.querySelectorAll('div').length
                };
            }
            
            function analyzeForms() {
                const forms = [];
                document.querySelectorAll('form').forEach((form, index) => {
                    const inputs = Array.from(form.querySelectorAll('input, textarea, select')).map(input => ({
                        type: input.type || input.tagName.toLowerCase(),
                        name: input.name,
                        placeholder: input.placeholder,
                        required: input.required
                    }));
                    
                    forms.push({
                        index: index,
                        action: form.action,
                        method: form.method,
                        inputs: inputs
                    });
                });
                return forms;
            }
            
            function analyzeLinks() {
                const links = [];
                document.querySelectorAll('a[href]').forEach((link, index) => {
                    if (index < 20) { // Limit to first 20 links
                        links.push({
                            text: (link.innerText || link.textContent || '').slice(0, 50),
                            href: link.href,
                            isExternal: link.hostname !== window.location.hostname,
                            hasTarget: !!link.target
                        });
                    }
                });
                return links;
            }
            
            function analyzeImages() {
                const images = [];
                document.querySelectorAll('img').forEach((img, index) => {
                    if (index < 10) { // Limit to first 10 images
                        images.push({
                            src: img.src,
                            alt: img.alt,
                            width: img.width,
                            height: img.height,
                            hasLazyLoading: img.loading === 'lazy'
                        });
                    }
                });
                return images;
            }
            
            function analyzeScripts() {
                const scripts = [];
                document.querySelectorAll('script[src]').forEach((script, index) => {
                    if (index < 10) { // Limit count
                        scripts.push({
                            src: script.src,
                            async: script.async,
                            defer: script.defer
                        });
                    }
                });
                return {
                    external: scripts,
                    inlineCount: document.querySelectorAll('script:not([src])').length
                };
            }
            
            function analyzeStyles() {
                const stylesheets = [];
                document.querySelectorAll('link[rel="stylesheet"]').forEach((link, index) => {
                    if (index < 10) { // Limit count
                        stylesheets.push({
                            href: link.href,
                            media: link.media
                        });
                    }
                });
                return {
                    external: stylesheets,
                    inlineCount: document.querySelectorAll('style').length
                };
            }
            
            function analyzeAccessibility() {
                return {
                    hasLang: !!document.querySelector('html[lang]'),
                    hasTitle: !!document.title,
                    altMissingCount: document.querySelectorAll('img:not([alt])').length,
                    headingStructure: checkHeadingStructure(),
                    ariaLabelsCount: document.querySelectorAll('[aria-label]').length,
                    landmarksCount: document.querySelectorAll('[role]').length
                };
            }
            
            function checkHeadingStructure() {
                const headings = Array.from(document.querySelectorAll('h1, h2, h3, h4, h5, h6'));
                const levels = headings.map(h => parseInt(h.tagName.charAt(1)));
                return {
                    hasH1: levels.includes(1),
                    multipleH1: levels.filter(l => l === 1).length > 1,
                    skipLevels: checkSkippedLevels(levels)
                };
            }
            
            function checkSkippedLevels(levels) {
                for (let i = 1; i < levels.length; i++) {
                    if (levels[i] - levels[i-1] > 1) {
                        return true;
                    }
                }
                return false;
            }
            
            function analyzePerformance() {
                return {
                    imagesCount: document.querySelectorAll('img').length,
                    scriptsCount: document.querySelectorAll('script').length,
                    stylesheetsCount: document.querySelectorAll('link[rel="stylesheet"]').length,
                    domSize: document.querySelectorAll('*').length,
                    loadTime: performance.timing ? 
                        performance.timing.loadEventEnd - performance.timing.navigationStart : null
                };
            }
            
            function analyzeSEO() {
                const title = document.title;
                const description = document.querySelector('meta[name="description"]')?.content;
                const keywords = document.querySelector('meta[name="keywords"]')?.content;
                const ogTitle = document.querySelector('meta[property="og:title"]')?.content;
                const ogDescription = document.querySelector('meta[property="og:description"]')?.content;
                
                return {
                    title: title,
                    titleLength: title.length,
                    description: description,
                    descriptionLength: description?.length || 0,
                    keywords: keywords,
                    hasOpenGraph: !!(ogTitle || ogDescription),
                    h1Count: document.querySelectorAll('h1').length,
                    canonicalUrl: document.querySelector('link[rel="canonical"]')?.href
                };
            }
        })();
        """
    }
}

// MARK: - WKNavigationDelegate

extension WebViewAnalyzer: WKNavigationDelegate {
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("🌐 WebView finished loading, starting content extraction...")
        
        // Set up message handlers for JavaScript communication
        setupMessageHandlers(webView)
        
        // Extract content after a short delay to ensure JavaScript execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.extractWebContent(from: webView)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView navigation failed: \(error.localizedDescription)")
        
        let failureResult = WebAnalysisResult.failure("Failed to load webpage: \(error.localizedDescription)")
        analysisCompletion?(failureResult)
        analysisCompletion = nil
    }
    
    private func setupMessageHandlers(_ webView: WKWebView) {
        let resultHandler = WebViewMessageHandler { [weak self] message in
            self?.handleAnalysisResults(message)
        }
        
        let errorHandler = WebViewMessageHandler { [weak self] message in
            self?.handleAnalysisError(message)
        }
        
        webView.configuration.userContentController.add(resultHandler, name: "analysisResults")
        webView.configuration.userContentController.add(errorHandler, name: "analysisError")
    }
    
    private func extractWebContent(from webView: WKWebView) {
        // Fallback extraction if JavaScript doesn't work
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, error in
            if let htmlString = result as? String {
                self?.processHTMLContent(htmlString, url: webView.url?.absoluteString ?? "")
            } else if let error = error {
                print("❌ Failed to extract HTML: \(error.localizedDescription)")
                let failureResult = WebAnalysisResult.failure("Failed to extract web content: \(error.localizedDescription)")
                self?.analysisCompletion?(failureResult)
                self?.analysisCompletion = nil
            }
        }
    }
    
    private func handleAnalysisResults(_ message: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let analysisData = try? JSONDecoder().decode(WebContentData.self, from: data) else {
            let failureResult = WebAnalysisResult.failure("Failed to parse web content data")
            analysisCompletion?(failureResult)
            analysisCompletion = nil
            return
        }
        
        let result = WebAnalysisResult.success(analysisData)
        analysisCompletion?(result)
        analysisCompletion = nil
    }
    
    private func handleAnalysisError(_ message: Any) {
        let errorMessage = "JavaScript analysis error: \(message)"
        let failureResult = WebAnalysisResult.failure(errorMessage)
        analysisCompletion?(failureResult)
        analysisCompletion = nil
    }
    
    private func processHTMLContent(_ html: String, url: String) {
        // Basic HTML processing as fallback
        let basicData = WebContentData(
            url: url,
            title: extractTitle(from: html),
            metadata: [:],
            textContent: WebTextContent(
                main: extractTextContent(from: html),
                headings: [],
                paragraphs: [],
                lists: []
            ),
            structure: WebStructure(
                hasHeader: html.contains("<header"),
                hasNav: html.contains("<nav"),
                hasMain: html.contains("<main"),
                hasAside: html.contains("<aside"),
                hasFooter: html.contains("<footer"),
                sectionsCount: countOccurrences(of: "<section", in: html),
                articlesCount: countOccurrences(of: "<article", in: html),
                divsCount: countOccurrences(of: "<div", in: html)
            ),
            forms: [],
            links: [],
            images: [],
            scripts: WebScripts(external: [], inlineCount: 0),
            styles: WebStyles(external: [], inlineCount: 0),
            accessibility: WebAccessibility(
                hasLang: html.contains("html lang="),
                hasTitle: !extractTitle(from: html).isEmpty,
                altMissingCount: 0,
                headingStructure: WebHeadingStructure(hasH1: html.contains("<h1"), multipleH1: false, skipLevels: false),
                ariaLabelsCount: 0,
                landmarksCount: 0
            ),
            performance: WebPerformance(
                imagesCount: countOccurrences(of: "<img", in: html),
                scriptsCount: countOccurrences(of: "<script", in: html),
                stylesheetsCount: countOccurrences(of: "stylesheet", in: html),
                domSize: 0,
                loadTime: nil
            ),
            seo: WebSEO(
                title: extractTitle(from: html),
                titleLength: extractTitle(from: html).count,
                description: nil,
                descriptionLength: 0,
                keywords: nil,
                hasOpenGraph: html.contains("og:"),
                h1Count: countOccurrences(of: "<h1", in: html),
                canonicalUrl: nil
            )
        )
        
        let result = WebAnalysisResult.success(basicData)
        analysisCompletion?(result)
        analysisCompletion = nil
    }
    
    private func extractTitle(from html: String) -> String {
        if let range = html.range(of: "<title>(.*?)</title>", options: .regularExpression) {
            let title = String(html[range])
            return title.replacingOccurrences(of: "<title>", with: "").replacingOccurrences(of: "</title>", with: "")
        }
        return "Unknown Title"
    }
    
    private func extractTextContent(from html: String) -> String {
        // Basic text extraction (remove HTML tags)
        return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(2000).description
    }
    
    private func countOccurrences(of substring: String, in string: String) -> Int {
        return string.components(separatedBy: substring).count - 1
    }
}

// MARK: - Message Handler

class WebViewMessageHandler: NSObject, WKScriptMessageHandler {
    private let handler: (Any) -> Void
    
    init(handler: @escaping (Any) -> Void) {
        self.handler = handler
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handler(message.body)
    }
}

// MARK: - Data Structures

enum WebAnalysisResult {
    case success(WebContentData)
    case failure(String)
    
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
    
    var data: WebContentData? {
        if case .success(let data) = self { return data }
        return nil
    }
    
    var errorMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}

struct WebContentData: Codable {
    let url: String
    let title: String
    let metadata: [String: String]
    let textContent: WebTextContent
    let structure: WebStructure
    let forms: [WebForm]
    let links: [WebLink]
    let images: [WebImage]
    let scripts: WebScripts
    let styles: WebStyles
    let accessibility: WebAccessibility
    let performance: WebPerformance
    let seo: WebSEO
}

struct WebTextContent: Codable {
    let main: String
    let headings: [WebHeading]
    let paragraphs: [WebParagraph]
    let lists: [WebList]
}

struct WebHeading: Codable {
    let level: Int
    let text: String
    let id: String?
}

struct WebParagraph: Codable {
    let index: Int
    let text: String
}

struct WebList: Codable {
    let type: String
    let items: [String]
}

struct WebStructure: Codable {
    let hasHeader: Bool
    let hasNav: Bool
    let hasMain: Bool
    let hasAside: Bool
    let hasFooter: Bool
    let sectionsCount: Int
    let articlesCount: Int
    let divsCount: Int
}

struct WebForm: Codable {
    let index: Int
    let action: String?
    let method: String?
    let inputs: [WebFormInput]
}

struct WebFormInput: Codable {
    let type: String
    let name: String?
    let placeholder: String?
    let required: Bool
}

struct WebLink: Codable {
    let text: String
    let href: String
    let isExternal: Bool
    let hasTarget: Bool
}

struct WebImage: Codable {
    let src: String
    let alt: String?
    let width: Int
    let height: Int
    let hasLazyLoading: Bool
}

struct WebScripts: Codable {
    let external: [WebExternalScript]
    let inlineCount: Int
}

struct WebExternalScript: Codable {
    let src: String
    let async: Bool
    let `defer`: Bool
}

struct WebStyles: Codable {
    let external: [WebExternalStyle]
    let inlineCount: Int
}

struct WebExternalStyle: Codable {
    let href: String
    let media: String?
}

struct WebAccessibility: Codable {
    let hasLang: Bool
    let hasTitle: Bool
    let altMissingCount: Int
    let headingStructure: WebHeadingStructure
    let ariaLabelsCount: Int
    let landmarksCount: Int
}

struct WebHeadingStructure: Codable {
    let hasH1: Bool
    let multipleH1: Bool
    let skipLevels: Bool
}

struct WebPerformance: Codable {
    let imagesCount: Int
    let scriptsCount: Int
    let stylesheetsCount: Int
    let domSize: Int
    let loadTime: Double?
}

struct WebSEO: Codable {
    let title: String
    let titleLength: Int
    let description: String?
    let descriptionLength: Int
    let keywords: String?
    let hasOpenGraph: Bool
    let h1Count: Int
    let canonicalUrl: String?
}