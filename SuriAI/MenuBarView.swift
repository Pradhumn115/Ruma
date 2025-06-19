//
//  MenuBarView.swift
//  SuriAI
//
//  Created by Pradhumn Gupta on 30/05/25.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        
//        Button("Open Model Hub") {
//            openWindow(id: "ModelHubWindow")
//        }
//
//        Divider()
        
        Button("Quit"){
            PythonScriptRunner.shared.stopPythonScript()
            NSApp.terminate(nil)
            
        }
     
    }
}

#Preview {
    MenuBarView()
}
