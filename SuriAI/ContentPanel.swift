
import SwiftUI
import AppKit


//class FloatingWindowView {
//    
//    static var window: NSWindow?
//    
//    
//    static func showFloatingWindow<Content: View>(view: Content) {
//        
//        let window = NSWindow(
//            contentRect: NSRect(x: 200, y: 200, width: 300, height: 200),
//            styleMask: [.borderless],
//            backing: .buffered,
//            defer: false
//        )
//        
//        window.level = .floating
//        window.isOpaque = false
//        window.hasShadow = true
//        window.backgroundColor = .clear
//        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
//        window.ignoresMouseEvents = false
//        window.isMovableByWindowBackground = true
//        window.isReleasedWhenClosed = false
//        let hostingView = NSHostingView(rootView: view)
//        window.contentView = hostingView.view
//        window.makeKeyAndOrderFront(nil)
//       
//        Self.window = window
//    }
//    
//    static func close() {
//        Self.window?.close()
//        Self.window = nil
//    }
//    
//}

class ContentPanel: NSPanel {
    
    private let focusModel = FocusModel()
    
    init(){
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .titled,.resizable],
            backing: .buffered,
            defer: true
        )
        
        setupWindow()
        setupContentView()
    }
    
    private func setupWindow() {
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        level = .floating
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary
        ]
     
    }
    
    private func setupContentView(){
        let updater = WindowSizeUpdater()
        updater.panel = self
        
        
        
        
        let contentView = ContentView() {
            self.close()
        }
            .environmentObject(updater) // inject into SwiftUI
            .environmentObject(focusModel)
//        let contentView = ContentView()
//            .environmentObject(updater) // inject into SwiftUI
//            .environmentObject(focusModel)
            
        
        
        
        let hostingView = NSHostingView(rootView: contentView)
        self.contentView = hostingView
        
        hostingView.setFrameSize(hostingView.fittingSize)

        
        if let screen = NSScreen.main {
            let padding: CGFloat = 20
            let ScreenFrame = screen.visibleFrame
            let xPosition = ScreenFrame.maxX/2 - padding
            let yPostion = ScreenFrame.maxY/2 + padding
            
            setFrameOrigin(NSPoint(x: xPosition, y: yPostion))
            setContentSize(hostingView.frame.size)

            
        }
        
    }
    
    func focusTextField(){
        // 🔥 Focus the text field after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.focusModel.focusTextField = true
        }
    }

    
    
}


class WindowSizeUpdater: ObservableObject {
    weak var panel: ContentPanel?

    func updateSize(to newSize: CGSize) {
        guard let panel = panel else { return }
        var frame = panel.frame
        let heightDiff = newSize.height - frame.size.height
        frame.origin.y -= heightDiff  // so it expands from top
        frame.size = newSize
        panel.setFrame(frame, display: true, animate: true)
    }
}
