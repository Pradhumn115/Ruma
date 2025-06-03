//
//  FloatingWindow2App.swift
//  FloatingWindow2
//
//  Created by Pradhumn Gupta on 25/05/25.
//

import SwiftUI
import AppKit

@main
struct SuriAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        
        MenuBarExtra{
            MenuBarView()
        }label: {
            Label("Suri AI", image: "menuBarLogo") // Custom image
        }
    }
}




