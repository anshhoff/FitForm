//
//  ContentView.swift
//  FitForm
//
//  Created by Ansh Hardaha on 16/10/25.
//  Main workout screen with camera, pose detection, and real-time feedback
//

import SwiftUI

/// Main workout screen that combines camera preview, pose detection, and user interface
/// Provides real-time squat form analysis and repetition counting
struct ContentView: View {
    
    // MARK: - View Model
    
    /// Central view model managing the complete workout pipeline
    @StateObject private var workoutViewModel = WorkoutViewModel()
    
    // MARK: - Animation State
    
    /// Controls UI animations and transitions
    @State private var isUIVisible = false
    @State private var buttonScale: CGFloat = 1.0
    @State private var isSettingsPresented = false
    @State private var showInstructionCard = true
    @State private var showRedPulse = false
    @State private var showGreenGlow = false
    @State private var workoutStartTime: Date? = nil
    @State private var distanceUIHiddenAfterOptimal: Bool = false
    
    /// Visual alert overlay state
    @State private var showPostureAlert = false
    @State private var postureAlertColor: Color = .green
    @State private var lastFormScore: Int = 0
    
    // MARK: - Body
    
    var body: some View {
        ZStack {
            // Layer 1: Camera Preview (Background)
            cameraPreviewLayer
            
            // Layer 2: Pose Skeleton Overlay (Middle)
            if workoutViewModel.isSkeletonOverlayEnabled {
                poseOverlayLayer
            }
            
            // Layer 3: UI Controls and Feedback (Top)
            uiOverlayLayer
            
            // Layer 4: Visual Alert Overlay
            postureAlertOverlay
            
            // Layer 5: Instruction Card (first 5 seconds)
            if showInstructionCard {
                instructionCard
                    .transition(.opacity)
            }
            
            // Layer 6: Visual Indicators (glow/pulse & distance icon)
            visualIndicatorsOverlay
            
            // Compact distance bar at the very top
            if shouldShowDistanceUI {
                distanceBarView
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(.all, edges: .all)
        .onAppear {
            setupInitialState()
            // Auto-dismiss instruction after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showInstructionCard = false
                }
            }
        }
        .onChange(of: workoutViewModel.isActive) { _, active in
            if active {
                workoutStartTime = Date()
                distanceUIHiddenAfterOptimal = false
            } else {
                workoutStartTime = nil
                distanceUIHiddenAfterOptimal = false
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isUIVisible)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: buttonScale)
        .onChange(of: workoutViewModel.formScore) { _, newScore in
            checkPostureChange(newScore: newScore)
            // Toggle green glow when form is perfect (>= 85 score)
            withAnimation(.easeInOut(duration: 0.25)) {
                showGreenGlow = newScore >= 85
            }
        }
        .onChange(of: workoutViewModel.isOptimalDistance) { _, optimal in
            // Hide distance UI after first 10s once optimal is achieved
            if optimal, !distanceUIHiddenAfterOptimal {
                if let start = workoutStartTime, Date().timeIntervalSince(start) >= 10 {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        distanceUIHiddenAfterOptimal = true
                    }
                }
            }
        }
    }
    
    // MARK: - Layer Components
    
    /// Camera preview background layer
    private var cameraPreviewLayer: some View {
        Group {
            if workoutViewModel.isCameraAuthorized {
                // Full-screen camera preview
                CameraPreviewView(session: workoutViewModel.captureSession)
                    .ignoresSafeArea(.all)
            } else {
                // Camera permission placeholder
                cameraPermissionView
            }
        }
    }
    
    /// Pose skeleton overlay layer
    private var poseOverlayLayer: some View {
        PoseOverlayView(jointPositions: workoutViewModel.jointPoints)
            .opacity(workoutViewModel.isPoseTracked ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: workoutViewModel.isPoseTracked)
    }
    
    /// UI controls and feedback overlay layer
    private var uiOverlayLayer: some View {
        VStack(spacing: 0) {
            // Top feedback banner
            ZStack(alignment: .topTrailing) {
                topFeedbackBanner
                
                // Settings button
                Button(action: { isSettingsPresented = true }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white)
                        .padding(10)
                        .background(.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .padding(.trailing, 24)
                .padding(.top, 24)
            }
            
            Spacer()
            
            // Loading indicator, large rep display, or bottom controls
            if workoutViewModel.isLoading {
                loadingIndicator
            } else if workoutViewModel.isActive {
                largeRepDisplay
            } else {
                bottomControlsCard
            }
        }
        .opacity(isUIVisible ? 1.0 : 0.0)
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView(
                isSpeechEnabled: $workoutViewModel.isSpeechEnabled,
                isSkeletonOverlayEnabled: $workoutViewModel.isSkeletonOverlayEnabled,
                isHapticsEnabled: $workoutViewModel.isHapticsEnabled,
                isSoundEnabled: $workoutViewModel.isSoundEnabled
            )
        }
    }
    
    // MARK: - UI Components
    
    /// Top banner showing real-time feedback
    private var topFeedbackBanner: some View {
        VStack(spacing: 12) {
            // Large form feedback message
            Text(workoutViewModel.feedbackMessage)
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
            
            // Form quality indicator
            if workoutViewModel.isPoseTracked {
                formQualityIndicator
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
        .padding(.top, 70) // Account for status bar
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 5)
    }
    
    /// Form quality progress indicator
    private var formQualityIndicator: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .foregroundColor(.white)
                .font(.caption)
            
            ProgressView(value: Double(workoutViewModel.formScore), total: 100.0)
                .progressViewStyle(LinearProgressViewStyle(tint: formQualityColor))
                .scaleEffect(y: 2.0)
            
            Text("\(workoutViewModel.formScore)%")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .frame(width: 35, alignment: .trailing)
        }
    }
    
    /// Large rep counter display for active workouts
    private var largeRepDisplay: some View {
        VStack(spacing: 16) {
            // Massive rep count number
            Text("\(workoutViewModel.repCount)")
                .font(.system(size: 72, weight: .heavy))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 3)
            
            // "Reps" label
            Text("REPS")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
                .tracking(2)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
            
            // Current squat state indicator
            Text(workoutViewModel.currentSquatState.rawValue.uppercased())
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(stateColor)
                .tracking(1)
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 2)
            
            // Large stop button
            largeStopButton
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 30)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 25)
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 50)
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 8)
    }
    
    /// Bottom card with stats and controls
    private var bottomControlsCard: some View {
        VStack(spacing: 20) {
            // Workout statistics
            workoutStatsView
            
            // Main control button
            mainControlButton
            
            // Secondary actions
            secondaryActionsView
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 40) // Account for home indicator
    }
    
    /// Workout statistics display
    private var workoutStatsView: some View {
        HStack(spacing: 30) {
            // Rep count
            StatItemView(
                icon: "arrow.up.arrow.down.circle.fill",
                title: "Reps",
                value: "\(workoutViewModel.repCount)",
                color: .blue
            )
            
            // Current state
            StatItemView(
                icon: stateIcon,
                title: "State",
                value: workoutViewModel.currentSquatState.rawValue,
                color: stateColor
            )
            
            // Knee angle (if available)
            if let angle = workoutViewModel.currentKneeAngle {
                StatItemView(
                    icon: "angle",
                    title: "Angle",
                    value: "\(Int(angle))°",
                    color: .orange
                )
            }
        }
    }
    
    /// Large stop button for active workout
    private var largeStopButton: some View {
        Button(action: {
            // Button animation
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                buttonScale = 0.95
            }
            
            // Reset scale after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    buttonScale = 1.0
                }
            }
            
            // Stop workout
            workoutViewModel.stop()
        }) {
            HStack(spacing: 16) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                
                Text("STOP WORKOUT")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing))
            )
            .shadow(color: .red.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .scaleEffect(buttonScale)
    }
    
    /// Main start/stop control button
    private var mainControlButton: some View {
        Button(action: {
            // Button animation
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                buttonScale = 0.95
            }
            
            // Reset scale after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                    buttonScale = 1.0
                }
            }
            
            // Toggle workout
            workoutViewModel.toggleWorkout()
        }) {
            HStack(spacing: 16) {
                Image(systemName: workoutViewModel.isActive ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                
                Text(workoutViewModel.isActive ? "STOP WORKOUT" : "START WORKOUT")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(1)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(workoutViewModel.isActive ? 
                          LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [.green, .green.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    )
            )
            .shadow(color: workoutViewModel.isActive ? .red.opacity(0.4) : .green.opacity(0.4), radius: 8, x: 0, y: 4)
        }
        .scaleEffect(buttonScale)
        .disabled(!workoutViewModel.isCameraAuthorized)
    }
    
    /// Secondary action buttons
    private var secondaryActionsView: some View {
        HStack(spacing: 16) {
            // Reset button
            Button(action: {
                workoutViewModel.resetWorkout()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Reset")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.2))
                )
            }
            .disabled(!workoutViewModel.isActive && workoutViewModel.repCount == 0)
            
            // Sound toggle button
            Button(action: {
                workoutViewModel.toggleSoundFeedback()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: workoutViewModel.isSoundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    Text("Sound")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(workoutViewModel.isSoundEnabled ? Color.blue.opacity(0.3) : Color.white.opacity(0.2))
                )
            }
            
            Spacer()
            
            // Rep progress indicator
            if workoutViewModel.isActive {
                repProgressIndicator
            }
        }
    }
    
    /// Rep progress circular indicator
    private var repProgressIndicator: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.3), lineWidth: 3)
                .frame(width: 40, height: 40)
            
            Circle()
                .trim(from: 0, to: workoutViewModel.repProgress)
                .stroke(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: workoutViewModel.repProgress)
            
            Text("\(Int(workoutViewModel.repProgress * 100))%")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
    
    /// Camera permission request view
    private var cameraPermissionView: some View {
        VStack(spacing: 24) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.8))
            
            VStack(spacing: 12) {
                Text("Camera Access Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("FitForm needs camera access to analyze your workout form and count repetitions.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("Grant Camera Permission") {
                // Open Settings app
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white)
            )
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.8), .purple.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    /// Loading indicator while camera initializes
    private var loadingIndicator: some View {
        VStack(spacing: 20) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            
            Text("Initializing Camera...")
                .font(.headline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.bottom, 40)
    }
    
    /// Visual alert overlay for posture changes
    private var postureAlertOverlay: some View {
        Rectangle()
            .fill(postureAlertColor.opacity(showPostureAlert ? 0.3 : 0.0))
            .ignoresSafeArea(.all)
            .animation(.easeInOut(duration: 0.3), value: showPostureAlert)
            .allowsHitTesting(false)
    }
    
    /// Semi-transparent instruction card shown at start
    private var instructionCard: some View {
        VStack(spacing: 12) {
            Text("Stand 6-8 feet from camera")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
            Text("Ensure full body is visible")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            Text("Start when ready")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        )
        .padding(.top, 120)
    }
    
    /// Visual indicators overlay: green glow, red pulse, distance icon
    private var visualIndicatorsOverlay: some View {
        ZStack {
            // Green glow for perfect form
            if showGreenGlow {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(LinearGradient(colors: [.green.opacity(0.8), .green.opacity(0.2)], startPoint: .top, endPoint: .bottom), lineWidth: 8)
                    .blur(radius: 10)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // Red pulse for corrections
            if showRedPulse {
                Circle()
                    .fill(Color.red.opacity(0.15))
                    .frame(width: 260, height: 260)
                    .scaleEffect(showRedPulse ? 1.1 : 0.9)
                    .animation(.easeInOut(duration: 0.5).repeatCount(1, autoreverses: true), value: showRedPulse)
                    .allowsHitTesting(false)
            }
            
            // Distance indicator icon (top-left) - only during initial guidance window
            if shouldShowDistanceUI {
                HStack {
                    let iconName: String = workoutViewModel.isOptimalDistance ? "checkmark.seal.fill" : (workoutViewModel.isTooClose ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    let iconColor: Color = workoutViewModel.isOptimalDistance ? .green : (workoutViewModel.isTooClose ? .red : .orange)
                    Image(systemName: iconName)
                        .foregroundColor(iconColor)
                        .padding(10)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                        .padding(.leading, 20)
                        .padding(.top, 20)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .allowsHitTesting(false)
    }

    /// Compact distance bar view (Too Close | Optimal | Too Far)
    private var distanceBarView: some View {
        HStack(spacing: 6) {
            distanceSegment(title: "Too Close", color: .red, active: workoutViewModel.isTooClose)
            distanceSegment(title: "Optimal", color: .green, active: workoutViewModel.isOptimalDistance)
            distanceSegment(title: "Too Far", color: .orange, active: (!workoutViewModel.isTooClose && !workoutViewModel.isOptimalDistance))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.35))
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .top)
    }
    
    private func distanceSegment(title: String, color: Color, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(active ? color : color.opacity(0.3))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.caption2)
                .foregroundColor(active ? .white : .white.opacity(0.6))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(active ? color : Color.white.opacity(0.2), lineWidth: active ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(active ? color.opacity(0.15) : Color.clear)
                )
        )
    }

    /// Whether distance UI should be shown given timing and state
    private var shouldShowDistanceUI: Bool {
        guard workoutViewModel.isActive else { return false }
        if distanceUIHiddenAfterOptimal { return false }
        guard let start = workoutStartTime else { return true }
        // Show for first 10 seconds; hide once optimal has been achieved and the 10s window passed
        let withinWindow = Date().timeIntervalSince(start) < 10
        return withinWindow || (!distanceUIHiddenAfterOptimal && !workoutViewModel.isOptimalDistance)
    }
    
    // MARK: - Helper Methods
    
    /// Sets up initial view state and starts camera
    private func setupInitialState() {
        // Animate UI appearance
        withAnimation(.easeInOut(duration: 0.5).delay(0.2)) {
            isUIVisible = true
        }
        
        // Start camera when view appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            workoutViewModel.start()
        }
    }
    
    /// Checks for significant posture changes and triggers visual alert
    /// - Parameter newScore: New form quality score
    private func checkPostureChange(newScore: Int) {
        guard workoutViewModel.isActive && workoutViewModel.isPoseTracked else { return }
        
        // Check for significant score changes (threshold of 20 points)
        let scoreDifference = abs(newScore - lastFormScore)
        
        if scoreDifference >= 20 && lastFormScore != 0 {
            // Determine alert color based on score improvement/degradation
            postureAlertColor = newScore > lastFormScore ? .green : .red
            
            // Trigger flash animation
            withAnimation(.easeInOut(duration: 0.2)) {
                showPostureAlert = true
            }
            
            // Hide alert after brief display
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showPostureAlert = false
                }
            }
        }
        
        lastFormScore = newScore
    }
    
    // MARK: - Computed Properties
    
    /// Form quality color based on score
    private var formQualityColor: Color {
        switch workoutViewModel.formScore {
        case 80...100: return .green
        case 60...79: return .yellow
        case 40...59: return .orange
        default: return .red
        }
    }
    
    /// State-specific icon
    private var stateIcon: String {
        switch workoutViewModel.currentSquatState {
        case .standing: return "figure.stand"
        case .descending: return "arrow.down.circle"
        case .bottom: return "arrow.down.to.line"
        case .ascending: return "arrow.up.circle"
        }
    }
    
    /// State-specific color
    private var stateColor: Color {
        switch workoutViewModel.currentSquatState {
        case .standing: return .green
        case .descending: return .blue
        case .bottom: return .purple
        case .ascending: return .orange
        }
    }
}

// MARK: - Supporting Views

/// Reusable stat item component
struct StatItemView: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
