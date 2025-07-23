//
//  MenuBarView.swift
//  SuriAI
//
//  Created by Pradhumn Gupta on 30/05/25.
//

import SwiftUI

struct MenuBarViewLegacy: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        
        Button("Open Model Hub") {
            openWindow(id: "ModelHubWindow")
        }

        Button("Memory Management") {
            openWindow(id: "MemoryManagementWindow")
        }

        Divider()
        
        Button("Quit"){
            PythonScriptRunner.shared.stopPythonScript()
            NSApp.terminate(nil)
            
        }
     
    }
}

#Preview {
    MenuBarViewLegacy()
}
