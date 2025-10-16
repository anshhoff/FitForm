//
//  PoseOverlayView.swift
//  FitForm
//
//  Created on 10/16/2025.
//  SwiftUI Canvas overlay for drawing human pose skeleton
//

import SwiftUI

/// SwiftUI view that draws a skeleton overlay on top of camera feed
/// Uses Canvas for high-performance drawing of pose joints and connections
struct PoseOverlayView: View {
    
    // MARK: - Properties
    
    /// Dictionary of joint positions with normalized coordinates (0-1)
    let jointPositions: [String: CGPoint]
    
    /// Animation state for smooth joint transitions
    @State private var animatedJoints: [String: CGPoint] = [:]
    
    // MARK: - Visual Configuration
    
    /// Joint circle radius in points
    private let jointRadius: CGFloat = 8
    
    /// Skeleton line width in points
    private let lineWidth: CGFloat = 3
    
    /// Colors for different body sides
    private let leftSideColor = Color.blue
    private let rightSideColor = Color.green
    
    /// Neck and nose color (neutral)
    private let neutralColor = Color.orange
    
    /// Overall opacity for semi-transparency
    private let overlayOpacity: Double = 0.8
    
    /// Animation duration for smooth transitions
    private let animationDuration: Double = 0.1
    
    // MARK: - Skeleton Connection Definitions
    
    /// Defines which joints connect to form the skeleton structure
    /// Each tuple represents a connection: (startJoint, endJoint, color)
    private let skeletonConnections: [(String, String, Color)] = [
        // Torso connections
        ("neck", "leftShoulder", .blue),
        ("neck", "rightShoulder", .green),
        ("leftShoulder", "leftHip", .blue),
        ("rightShoulder", "rightHip", .green),
        
        // Arm connections - Left side
        ("leftShoulder", "leftElbow", .blue),
        ("leftElbow", "leftWrist", .blue),
        
        // Arm connections - Right side
        ("rightShoulder", "rightElbow", .green),
        ("rightElbow", "rightWrist", .green),
        
        // Leg connections - Left side
        ("leftHip", "leftKnee", .blue),
        ("leftKnee", "leftAnkle", .blue),
        
        // Leg connections - Right side
        ("rightHip", "rightKnee", .green),
        ("rightKnee", "rightAnkle", .green)
    ]
    
    // MARK: - Body
    
    var body: some View {
        Canvas { context, size in
            // Draw the complete skeleton overlay
            drawSkeleton(context: context, size: size)
        }
        .opacity(overlayOpacity)
        .allowsHitTesting(false) // Allow touches to pass through to camera
        .onChange(of: jointPositions) { _, newJoints in
            // Animate joint position changes for smooth transitions
            animateJointUpdates(newJoints: newJoints)
        }
        .onAppear {
            // Initialize animated joints with current positions
            animatedJoints = jointPositions
        }
    }
    
    // MARK: - Drawing Methods
    
    /// Draws the complete skeleton including joints and connections
    /// - Parameters:
    ///   - context: Canvas graphics context
    ///   - size: Available drawing size
    private func drawSkeleton(context: GraphicsContext, size: CGSize) {
        // First draw skeleton lines (behind joints)
        drawSkeletonLines(context: context, size: size)
        
        // Then draw joints (on top of lines)
        drawJoints(context: context, size: size)
    }
    
    /// Draws connecting lines between joints to form skeleton structure
    /// - Parameters:
    ///   - context: Canvas graphics context
    ///   - size: Available drawing size
    private func drawSkeletonLines(context: GraphicsContext, size: CGSize) {
        // Iterate through all defined skeleton connections
        for (startJoint, endJoint, color) in skeletonConnections {
            // Get positions for both joints
            guard let startPos = animatedJoints[startJoint],
                  let endPos = animatedJoints[endJoint] else {
                continue // Skip if either joint is missing
            }
            
            // Convert normalized coordinates to view coordinates
            let startPoint = normalizedToViewCoordinates(startPos, viewSize: size)
            let endPoint = normalizedToViewCoordinates(endPos, viewSize: size)
            
            // Create and draw the connection line
            var path = Path()
            path.move(to: startPoint)
            path.addLine(to: endPoint)
            
            // Apply line styling
            context.stroke(
                path,
                with: .color(color),
                style: StrokeStyle(
                    lineWidth: lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }
    
    /// Draws circles at each detected joint position
    /// - Parameters:
    ///   - context: Canvas graphics context
    ///   - size: Available drawing size
    private func drawJoints(context: GraphicsContext, size: CGSize) {
        // Draw each detected joint
        for (jointName, position) in animatedJoints {
            // Convert normalized coordinates to view coordinates
            let viewPosition = normalizedToViewCoordinates(position, viewSize: size)
            
            // Determine joint color based on body side
            let jointColor = getJointColor(for: jointName)
            
            // Create circle path for joint
            let jointCircle = Path { path in
                path.addEllipse(in: CGRect(
                    x: viewPosition.x - jointRadius,
                    y: viewPosition.y - jointRadius,
                    width: jointRadius * 2,
                    height: jointRadius * 2
                ))
            }
            
            // Draw joint circle with fill and stroke
            context.fill(jointCircle, with: .color(jointColor))
            context.stroke(
                jointCircle,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2)
            )
        }
    }
    
    // MARK: - Helper Methods
    
    /// Converts normalized coordinates (0-1) to view pixel coordinates
    /// - Parameters:
    ///   - normalizedPoint: Point with coordinates between 0 and 1
    ///   - viewSize: Size of the view in points
    /// - Returns: Point in view coordinate system
    private func normalizedToViewCoordinates(_ normalizedPoint: CGPoint, viewSize: CGSize) -> CGPoint {
        return CGPoint(
            x: normalizedPoint.x * viewSize.width,
            y: normalizedPoint.y * viewSize.height
        )
    }
    
    /// Determines the appropriate color for a joint based on body side
    /// - Parameter jointName: Name of the joint
    /// - Returns: Color to use for the joint
    private func getJointColor(for jointName: String) -> Color {
        if jointName.hasPrefix("left") {
            return leftSideColor
        } else if jointName.hasPrefix("right") {
            return rightSideColor
        } else {
            // Neutral joints like neck, nose
            return neutralColor
        }
    }
    
    /// Animates joint position updates for smooth transitions
    /// - Parameter newJoints: New joint positions to animate to
    private func animateJointUpdates(newJoints: [String: CGPoint]) {
        withAnimation(.easeInOut(duration: animationDuration)) {
            // Update only joints that exist in new positions
            for (jointName, newPosition) in newJoints {
                animatedJoints[jointName] = newPosition
            }
            
            // Remove joints that are no longer detected
            let newJointNames = Set(newJoints.keys)
            let currentJointNames = Set(animatedJoints.keys)
            let jointsToRemove = currentJointNames.subtracting(newJointNames)
            
            for jointName in jointsToRemove {
                animatedJoints.removeValue(forKey: jointName)
            }
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct PoseOverlayView_Previews: PreviewProvider {
    static var previews: some View {
        // Create sample joint positions for preview
        let sampleJoints: [String: CGPoint] = [
            "nose": CGPoint(x: 0.5, y: 0.2),
            "neck": CGPoint(x: 0.5, y: 0.3),
            "leftShoulder": CGPoint(x: 0.4, y: 0.35),
            "rightShoulder": CGPoint(x: 0.6, y: 0.35),
            "leftElbow": CGPoint(x: 0.35, y: 0.5),
            "rightElbow": CGPoint(x: 0.65, y: 0.5),
            "leftWrist": CGPoint(x: 0.3, y: 0.65),
            "rightWrist": CGPoint(x: 0.7, y: 0.65),
            "leftHip": CGPoint(x: 0.45, y: 0.6),
            "rightHip": CGPoint(x: 0.55, y: 0.6),
            "leftKnee": CGPoint(x: 0.43, y: 0.75),
            "rightKnee": CGPoint(x: 0.57, y: 0.75),
            "leftAnkle": CGPoint(x: 0.41, y: 0.9),
            "rightAnkle": CGPoint(x: 0.59, y: 0.9)
        ]
        
        ZStack {
            // Simulate camera background
            Rectangle()
                .fill(LinearGradient(
                    colors: [.gray.opacity(0.3), .gray.opacity(0.1)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            
            // Pose overlay
            PoseOverlayView(jointPositions: sampleJoints)
        }
        .frame(width: 300, height: 400)
        .previewDisplayName("Pose Overlay")
    }
}
#endif

// MARK: - Extensions

extension PoseOverlayView {
    
    /// Creates a pose overlay with custom styling
    /// - Parameters:
    ///   - jointRadius: Custom radius for joint circles
    ///   - lineWidth: Custom width for skeleton lines
    ///   - opacity: Custom opacity for the overlay
    /// - Returns: Configured pose overlay view
    func customStyling(
        jointRadius: CGFloat? = nil,
        lineWidth: CGFloat? = nil,
        opacity: Double? = nil
    ) -> some View {
        var view = self
        
        // Note: In a real implementation, these would be @State variables
        // that could be modified. For now, they're compile-time constants.
        
        return view.opacity(opacity ?? overlayOpacity)
    }
    
    /// Hides the overlay when no joints are detected
    /// - Returns: View that automatically hides when empty
    func hideWhenEmpty() -> some View {
        self.opacity(jointPositions.isEmpty ? 0 : overlayOpacity)
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLE:
 
 struct CameraView: View {
     @StateObject private var cameraManager = CameraManager()
     @StateObject private var poseDetector = PoseDetectionManager()
     
     var body: some View {
         ZStack {
             // Camera preview layer
             CameraPreviewView(session: cameraManager.captureSession)
                 .ignoresSafeArea()
             
             // Pose skeleton overlay
             PoseOverlayView(jointPositions: poseDetector.detectedJoints)
                 .hideWhenEmpty()
         }
         .onReceive(cameraManager.$currentFrame) { frame in
             if let pixelBuffer = frame {
                 poseDetector.processFrame(pixelBuffer)
             }
         }
     }
 }
 
 COORDINATE SYSTEM:
 - Input coordinates are normalized (0.0 to 1.0)
 - (0,0) = top-left corner of view
 - (1,1) = bottom-right corner of view
 - Automatically scales to any view size
 
 VISUAL DESIGN:
 - Left side joints/lines: Blue
 - Right side joints/lines: Green  
 - Neutral joints (neck, nose): Orange
 - Semi-transparent overlay (80% opacity)
 - Smooth animations between pose updates
 
 PERFORMANCE:
 - Uses Canvas for efficient drawing
 - Minimal redraws with targeted animations
 - Hit testing disabled for touch pass-through
 - Optimized for real-time pose tracking
 
 */
