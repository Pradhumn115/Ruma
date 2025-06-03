//
//  MenuBarView.swift
//  SuriAI
//
//  Created by Pradhumn Gupta on 30/05/25.
//

import SwiftUI

struct MenuBarView: View {

    
    var body: some View {
        Button("Quit"){
            PythonScriptRunner.shared.stopPythonScript()
            NSApp.terminate(nil)
            
        }
    }
}

#Preview {
    MenuBarView()
}
