//
//  AppDelegate.swift
//  FloatingWindow2
//
//  Created by Pradhumn Gupta on 31/05/25.
//

import Foundation
import AppKit
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    var contentWindow: NSWindow?
    var hotkey: HotKey?

    
    
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        setupHotkey()

        PythonScriptRunner.shared.runPostInstallScripts()
        PythonScriptRunner.shared.runPythonScript()
        
    }
    
    
    
    private func setupHotkey() {
        
        hotkey = HotKey(key: .a, modifiers: [.command,.shift])
        hotkey?.keyDownHandler = { [weak self ] in
            DispatchQueue.main.async {
                self?.showContentPanel()
            }
        }
    }
    
    
    func showContentPanel() {
        self.closeReviewWindow()
        
        let contentPanel = ContentPanel()
        
        contentWindow = contentPanel
        
        contentWindow?.makeKeyAndOrderFront(nil)
        
        contentPanel.makeKey()
        contentPanel.focusTextField()
        

        
        
        
        
        
    }
    
    private func closeReviewWindow() {
        if let window = contentWindow {
            window.close()
            contentWindow = nil
        }
    }
    
}


class PythonScriptRunner {
    
    static let shared = PythonScriptRunner()
    private var task: Process?
    
    func runPythonScript() {
        
        let pythonPath = Bundle.main.resourcePath! + "/suripython/app-suriai-app/bin/python3"
        let scriptPath = Bundle.main.resourcePath! + "/mlx_app.py"

        let task = Process()
        task.launchPath = pythonPath
        task.arguments = [scriptPath]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        task.terminationHandler = { process in
            let outputData = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? "No output"
            print("Python Output:\n\(output)")
        }
        
        self.task = task  // Save reference
        
        do {
            try task.run()
        } catch {
            print("Failed to run Python script: \(error)")
        }
    }
    
    func stopPythonScript() {

        if let task = task, task.isRunning {
            task.terminate()
            print("Python script terminated.")
        } else {
            
            print("No running task to terminate.")
        }
    }
    

    func runPostInstallScripts(){
        
        let resourcePath = Bundle.main.resourcePath
        
        print("Resource Path: \(resourcePath!)")
        
        
        let allArgs: [String] = [
            
            resourcePath! + "/suripython/app-suriai-app/postinstall.py",
            resourcePath! + "/suripython/framework-mlx-env/postinstall.py",
            resourcePath! + "/suripython/cpython@3.11/postinstall.py"
                            
        ]
        for arg in allArgs{
            
            let task = Process()
            let pipe = Pipe()
            
            task.standardOutput = pipe
            task.standardError = pipe
            
            task.arguments = [arg]
            
            task.launchPath = resourcePath! + "/suripython/cpython@3.11/bin/python3"
            task.standardInput = nil
            task.launch()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            
            let output = String(data: data, encoding: .utf8) ?? "No output"
            print(output,"Done Execution")
            
        }
       
        
    }




    
}
