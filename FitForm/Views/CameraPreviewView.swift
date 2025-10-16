//
//  CameraPreviewView.swift
//  FitForm
//
//  Created on 10/16/2025.
//  SwiftUI wrapper for AVCaptureVideoPreviewLayer
//

import SwiftUI
import AVFoundation

/// SwiftUI view that displays live camera preview using AVCaptureVideoPreviewLayer
/// Wraps UIKit's AVCaptureVideoPreviewLayer for use in SwiftUI
struct CameraPreviewView: UIViewRepresentable {
    
    // MARK: - Properties
    
    /// The capture session to display preview for
    let session: AVCaptureSession
    
    // MARK: - UIViewRepresentable Implementation
    
    /// Creates the underlying UIView (preview layer container)
    /// - Parameter context: The representable context
    /// - Returns: UIView containing the preview layer
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        // Create and configure the preview layer
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        
        // Configure layer properties for optimal display
        configurePreviewLayer(previewLayer, in: view)
        
        // Add the preview layer to the view
        view.layer.addSublayer(previewLayer)
        
        // Store reference to preview layer for updates
        view.layer.name = "CameraPreviewLayer"
        
        return view
    }
    
    /// Updates the UIView when SwiftUI state changes
    /// - Parameters:
    ///   - uiView: The UIView to update
    ///   - context: The representable context
    func updateUIView(_ uiView: UIView, context: Context) {
        // Find the preview layer
        guard let previewLayer = findPreviewLayer(in: uiView) else { return }
        
        // Update the session if it has changed
        if previewLayer.session !== session {
            previewLayer.session = session
        }
        
        // Ensure the layer frame matches the view bounds
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
    
    // MARK: - Coordinator (Optional - not needed for basic preview)
    
    /// Creates a coordinator for handling delegate methods if needed
    /// Currently not required for basic preview functionality
    /// Uncomment and implement if you need to handle preview layer delegate methods
    /*
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        let parent: CameraPreviewView
        
        init(_ parent: CameraPreviewView) {
            self.parent = parent
        }
    }
    */
    
    // MARK: - Private Helper Methods
    
    /// Configures the preview layer with optimal settings
    /// - Parameters:
    ///   - previewLayer: The preview layer to configure
    ///   - view: The container view
    private func configurePreviewLayer(_ previewLayer: AVCaptureVideoPreviewLayer, in view: UIView) {
        // Set the frame to fill the entire view
        previewLayer.frame = view.bounds
        
        // Configure video gravity for proper aspect ratio
        // .resizeAspectFill fills the screen without distortion, may crop edges
        // .resizeAspect fits entire image with possible letterboxing
        // .resize stretches to fill (may distort)
        previewLayer.videoGravity = .resizeAspectFill
        
        // Set the preview layer to update its frame automatically
        previewLayer.needsDisplayOnBoundsChange = true
        
        // Configure connection properties if available
        if let connection = previewLayer.connection {
            // Set video orientation to match device orientation
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
            
            // Enable video stabilization if supported
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = .auto
            }
        }
    }
    
    /// Finds the preview layer in the view hierarchy
    /// - Parameter view: The view to search in
    /// - Returns: The preview layer if found
    private func findPreviewLayer(in view: UIView) -> AVCaptureVideoPreviewLayer? {
        return view.layer.sublayers?.first { layer in
            layer is AVCaptureVideoPreviewLayer
        } as? AVCaptureVideoPreviewLayer
    }
}

// MARK: - Preview Provider

#if DEBUG
struct CameraPreviewView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock session for preview
        let mockSession = AVCaptureSession()
        
        CameraPreviewView(session: mockSession)
            .ignoresSafeArea() // Fill entire screen including safe areas
            .previewDisplayName("Camera Preview")
    }
}
#endif

// MARK: - View Modifiers

extension CameraPreviewView {
    
    /// Modifier to make the camera preview fill the entire screen
    /// - Returns: Modified view that ignores safe areas
    func fullScreen() -> some View {
        self.ignoresSafeArea(.all)
    }
    
    /// Modifier to set custom aspect ratio behavior
    /// - Parameter videoGravity: The video gravity mode to use
    /// - Returns: Modified view with custom video gravity
    func videoGravity(_ videoGravity: AVLayerVideoGravity) -> some View {
        self.onAppear {
            // This would require storing the video gravity and applying it
            // in makeUIView or updateUIView - implementation depends on needs
        }
    }
}

// MARK: - Usage Examples

/*
 Usage in SwiftUI:
 
 struct ContentView: View {
     @StateObject private var cameraManager = CameraManager()
     
     var body: some View {
         ZStack {
             // Camera preview fills entire screen
             CameraPreviewView(session: cameraManager.captureSession)
                 .fullScreen()
             
             // Overlay UI elements
             VStack {
                 Spacer()
                 
                 HStack {
                     Button("Start") {
                         cameraManager.start()
                     }
                     
                     Button("Stop") {
                         cameraManager.stop()
                     }
                 }
                 .padding()
             }
         }
     }
 }
 
 Alternative usage with specific frame:
 
 CameraPreviewView(session: cameraManager.captureSession)
     .frame(width: 300, height: 400)
     .cornerRadius(12)
     .clipped()
 
 */
