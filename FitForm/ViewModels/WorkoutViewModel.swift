//
//  WorkoutViewModel.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Central view model orchestrating the complete fitness pose estimation pipeline
//

import SwiftUI
import Combine
import AVFoundation
import AudioToolbox

/// Central view model that orchestrates the complete fitness tracking pipeline
/// Manages data flow from camera capture through pose estimation to user feedback
///
/// **DATA FLOW ARCHITECTURE:**
/// ```
/// Camera Frame (CVPixelBuffer)
///        ↓
/// PoseEstimator (Vision ML)
///        ↓
/// Joint Coordinates [String: CGPoint]
///        ↓        ↓
/// PostureAnalyzer  RepCounter
///        ↓        ↓
/// Form Feedback   Rep Count
///        ↓        ↓
/// SwiftUI Updates (Published Properties)
/// ```
@MainActor
class WorkoutViewModel: ObservableObject {
    
    // MARK: - Component Instances
    
    /// Camera manager for video capture and frame processing
    private let cameraManager = CameraManager()
    
    /// Pose estimator for extracting joint coordinates from camera frames
    private let poseEstimator = PoseEstimator()
    
    /// Rep counter for tracking squat repetitions with state machine
    private let repCounter = RepCounter()
    
    /// Speech manager for voice announcements and feedback
    private let speechManager = SpeechManager.shared
    
    /// Posture analyzer for form analysis with speech management
    private let postureAnalyzer = PostureAnalyzer.shared
    
    // MARK: - Published Properties for SwiftUI
    
    /// Current detected joint positions (normalized 0-1 coordinates)
    /// Used by PoseOverlayView for skeleton visualization
    @Published var jointPoints: [String: CGPoint] = [:]
    
    /// Current form feedback message from PostureAnalyzer
    /// Displayed to user for real-time coaching
    @Published var feedbackMessage: String = "Position yourself in camera view"
    
    /// Current repetition count from RepCounter
    /// Shows workout progress to user
    @Published var repCount: Int = 0
    
    /// Whether the workout session is currently active
    /// Controls UI state and processing pipeline
    @Published var isActive: Bool = false
    
    /// Current camera authorization status
    /// Used to show permission prompts if needed
    @Published var isCameraAuthorized: Bool = false
    
    /// Current knee angle for debugging/advanced UI
    /// Optional display for technical users
    @Published var currentKneeAngle: Double? = nil
    
    /// Current squat state from RepCounter
    /// Used for state-specific UI feedback
    @Published var currentSquatState: RepCounter.SquatState = .standing
    
    /// Form quality score (0-100) from PostureAnalyzer
    /// Visual indicator of exercise form quality
    @Published var formScore: Int = 0
    
    /// Error message for user display
    /// Shows any issues with camera, pose detection, etc.
    @Published var errorMessage: String? = nil
    
    /// Distance guidance flags
    @Published var isTooClose: Bool = false
    @Published var isOptimalDistance: Bool = false
    @Published var isTooFar: Bool = false
    
    /// Loading state while camera initializes
    /// Shows loading indicator during camera setup
    @Published var isLoading: Bool = false
    
    // MARK: - Private Properties
    
    /// Combine cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Processing queue for pose estimation (background thread)
    private let processingQueue = DispatchQueue(label: "com.fitform.processing", qos: .userInteractive)
    
    /// Debounce timer to limit pose processing frequency
    private var processingTimer: Timer?
    
    /// Last processed frame timestamp to control processing rate
    private var lastProcessingTime: Date = Date.distantPast
    
    /// Target processing interval (15 FPS = ~0.067 seconds for better performance)
    private let processingInterval: TimeInterval = 0.067
    
    /// Haptic feedback generator for rep completion
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    
    /// Sound feedback enabled state
    @Published var isSoundEnabled: Bool = true
    
    /// Voice announcements enabled state
    @Published var isSpeechEnabled: Bool = true
    
    /// Haptic feedback enabled state
    @Published var isHapticsEnabled: Bool = true
    
    /// Skeleton overlay visibility
    @Published var isSkeletonOverlayEnabled: Bool = true
    
    /// Minimal UI mode flag (shows only essential elements)
    @Published var isMinimalUIMode: Bool = false
    
    /// Speech anti-spam properties
    private var lastSpeechTime: Date = Date.distantPast
    private var lastSpokenMessage: String = ""
    private let minimumSpeechInterval: TimeInterval = 4.0
    private var lastRepCount: Int = 0
    private var lastFeedbackMessage: String = ""

    /// Distance speaking state
    private var distanceTooCloseStartTime: Date? = nil
    private var hasSpokenTooClose: Bool = false
    private var distanceCheckDebounce: Timer? = nil
    
    // MARK: - Initialization
    
    init() {
        setupBindings()
        setupCameraObservation()
        setupHapticFeedback()
        setupSpeechManagement()
    }
    
    // MARK: - Public Methods
    
    /// Starts the complete workout tracking pipeline
    /// Initializes camera, begins pose estimation, and starts rep counting
    func start() {
        guard !isActive else { return }
        
        isActive = true
        isLoading = true
        errorMessage = nil
        feedbackMessage = "Starting camera..."
        
        // Start camera capture
        cameraManager.start()
        
        // Reset rep counter for new session
        repCounter.reset()
        
        // Clear any previous joint data
        jointPoints.removeAll()
        
        // Stop loading after camera initialization delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isLoading = false
            if self.isCameraAuthorized {
                self.feedbackMessage = "Position yourself in camera view"
            }
        }
    }
    
    /// Stops the workout tracking pipeline
    /// Stops camera, clears data, and resets UI state
    func stop() {
        guard isActive else { return }
        
        isActive = false
        isLoading = false
        
        // Stop camera capture
        cameraManager.stop()
        
        // Clear processing timer
        processingTimer?.invalidate()
        processingTimer = nil
        
        // Reset UI state
        jointPoints.removeAll()
        feedbackMessage = "Workout stopped"
        currentKneeAngle = nil
        errorMessage = nil
        
        // Keep rep count for user review
    }
    
    /// Resets the current workout session
    /// Clears rep count and resets all tracking data
    func resetWorkout() {
        repCounter.reset()
        jointPoints.removeAll()
        feedbackMessage = isActive ? "Position yourself in camera view" : "Tap start to begin"
        currentKneeAngle = nil
        formScore = 0
        errorMessage = nil
        
        // Reset speech tracking
        lastRepCount = 0
        lastFeedbackMessage = ""
        lastSpeechTime = Date.distantPast
        postureAnalyzer.resetFeedbackTracking()
    }
    
    /// Toggles workout session (start/stop)
    /// Convenience method for single button control
    func toggleWorkout() {
        if isActive {
            stop()
        } else {
            start()
        }
    }
    
    /// Toggles sound feedback on/off
    /// Allows user to control audio feedback
    func toggleSoundFeedback() {
        isSoundEnabled.toggle()
    }
    
    /// Toggles voice announcements on/off
    /// Allows user to control speech feedback
    func toggleSpeechFeedback() {
        isSpeechEnabled.toggle()
    }
    
    // MARK: - Setup Methods
    
    /// Sets up Combine bindings between components
    /// Connects RepCounter updates to published properties
    private func setupBindings() {
        // Bind RepCounter properties to published properties
        repCounter.$repCount
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newCount in
                let oldCount = self?.repCount ?? 0
                self?.repCount = newCount
                
                // Trigger feedback when rep count increases
                if newCount > oldCount {
                    self?.triggerRepCompletionFeedback()
                    self?.announceRepCompletion(newCount)
                }
            }
            .store(in: &cancellables)
        
        repCounter.$currentState
            .receive(on: DispatchQueue.main)
            .assign(to: \.currentSquatState, on: self)
            .store(in: &cancellables)
        
        // Bind CameraManager authorization status
        cameraManager.$isAuthorized
            .receive(on: DispatchQueue.main)
            .assign(to: \.isCameraAuthorized, on: self)
            .store(in: &cancellables)
        
        // Bind CameraManager error messages
        cameraManager.$errorMessage
            .receive(on: DispatchQueue.main)
            .assign(to: \.errorMessage, on: self)
            .store(in: &cancellables)
    }
    
    /// Sets up haptic feedback generator
    /// Prepares haptic feedback for optimal performance
    private func setupHapticFeedback() {
        hapticFeedback.prepare()
    }
    
    /// Triggers haptic and sound feedback when rep is completed
    /// Provides multi-sensory feedback for rep completion
    private func triggerRepCompletionFeedback() {
        // Haptic feedback
        if isHapticsEnabled {
            hapticFeedback.impactOccurred()
        }
        
        // Sound feedback (if enabled)
        if isSoundEnabled {
            // Play system sound for rep completion
            AudioServicesPlaySystemSound(1057) // Pop sound
        }
    }
    
    /// Sets up speech management and voice announcements
    /// Configures speech settings and initializes voice feedback
    private func setupSpeechManagement() {
        // Configure speech manager settings
        speechManager.setSpeechEnabled(isSpeechEnabled)
        
        // Bind speech enabled state to speech manager
        $isSpeechEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                self?.speechManager.setSpeechEnabled(enabled)
            }
            .store(in: &cancellables)
    }
    
    /// Handles speech announcements for posture feedback
    /// - Parameter analysis: The posture analysis result with speech control
    private func handleFeedbackSpeech(analysis: PostureAnalyzer.SquatAnalysis) {
        // Only speak if speech is enabled and the analysis recommends it
        guard isSpeechEnabled && analysis.shouldSpeak else { return }
        
        // Announce feedback based on category
        switch analysis.feedbackCategory {
        case .positive:
            if shouldSpeak(message: analysis.primaryFeedback) {
                speechManager.speak(analysis.primaryFeedback)
            }
            
        case .corrective:
            if shouldSpeak(message: analysis.primaryFeedback) {
                speechManager.speakWorkoutFeedback(analysis.primaryFeedback, priority: true)
            }
            
        case .neutral:
            // Don't speak neutral messages to reduce noise
            break
        }
        lastFeedbackMessage = analysis.primaryFeedback
    }
    
    /// Announces rep completion with voice feedback
    /// - Parameter repCount: The current rep count
    private func announceRepCompletion(_ repCount: Int) {
        // Only speak if speech is enabled and rep count changed
        guard isSpeechEnabled && repCount != lastRepCount else { return }
        
        // Announce if not violating anti-spam
        let message = repCount == 1 ? "1 rep completed" : "\(repCount) reps completed"
        if shouldSpeak(message: message) {
            speechManager.speakRepCount(repCount)
        }
        
        // Update rep tracking
        lastRepCount = repCount
    }
    
    /// Sets up camera frame observation and processing pipeline
    /// Connects camera frames to pose estimation workflow
    private func setupCameraObservation() {
        // Observe camera frames and process through pipeline
        cameraManager.$currentFrame
            .compactMap { $0 } // Only process non-nil frames
            .receive(on: processingQueue) // Move to background thread
            .sink { [weak self] pixelBuffer in
                guard let self = self else { return }
                self.processFrame(pixelBuffer)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Frame Processing Pipeline
    
    /// Processes a camera frame through the complete pipeline
    /// - Parameter pixelBuffer: Camera frame to process
    ///
    /// **PROCESSING PIPELINE:**
    /// 1. Rate limiting (30 FPS max)
    /// 2. Pose estimation (Vision ML)
    /// 3. Joint coordinate extraction
    /// 4. Posture analysis (form feedback)
    /// 5. Rep counting (state machine)
    /// 6. UI updates (main thread)
    private func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Rate limiting: Don't process frames too frequently
        let now = Date()
        guard now.timeIntervalSince(lastProcessingTime) >= processingInterval else {
            return
        }
        lastProcessingTime = now
        
        // Only process if workout is active
        guard isActive else { return }
        
        // Step 1: Pose Estimation
        // Convert camera frame to joint coordinates using Vision ML
        poseEstimator.estimatePose(from: pixelBuffer) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let poseResult):
                // Step 2: Process successful pose detection
                self.processPoseDetection(joints: poseResult.joints)
                
                // Handle distance guidance UI and speech
                self.handleDistanceGuidance(bodyHeight: poseResult.bodyHeight,
                                             distanceState: poseResult.bodyDistance,
                                             tooClose: poseResult.bodyTooClose,
                                             optimal: poseResult.bodyOptimalDistance)
                
            case .failure(let error):
                // Step 3: Handle pose detection failure
                self.handlePoseDetectionError(error)
            }
        }
    }
    
    /// Processes successful pose detection results
    /// - Parameter joints: Detected joint coordinates
    ///
    /// **JOINT PROCESSING WORKFLOW:**
    /// 1. Update UI with joint positions (for skeleton overlay)
    /// 2. Analyze posture and form (PostureAnalyzer)
    /// 3. Update rep counting (RepCounter state machine)
    /// 4. Update all UI properties on main thread
    private func processPoseDetection(joints: [String: CGPoint]) {
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Step 1: Update joint positions for skeleton overlay
            self.jointPoints = joints
            
            // Step 2: Analyze posture and generate feedback with speech management
            let analysis = self.postureAnalyzer.analyzeSquatForm(joints: joints)
            self.feedbackMessage = analysis.primaryFeedback
            self.formScore = analysis.formScore
            self.currentKneeAngle = analysis.kneeAngle
            
            // Step 3: Handle speech announcements for feedback
            self.handleFeedbackSpeech(analysis: analysis)
            
            // Step 3: Update rep counting with knee angle
            if let kneeAngle = analysis.kneeAngle {
                self.repCounter.updateKneeAngle(kneeAngle)
            }
            
            // Step 4: Clear any previous errors
            self.errorMessage = nil
        }
    }

    /// Determines whether a message should be spoken to avoid spam
    /// - Parameter message: Message to consider
    /// - Returns: True if message should be spoken now
    private func shouldSpeak(message: String) -> Bool {
        let now = Date()
        // Block if same message or minimum interval not elapsed
        if message == lastSpokenMessage { return false }
        if now.timeIntervalSince(lastSpeechTime) < minimumSpeechInterval { return false }
        
        // Allow speak and update state
        lastSpokenMessage = message
        lastSpeechTime = now
        return true
    }

    // MARK: - Distance Guidance
    
    /// Shows guidance to help user adjust distance to camera
    /// - Parameters:
    ///   - span: Vertical span 0-1
    ///   - tooClose: True if span < threshold
    ///   - optimal: True if span > optimal threshold
    private var currentBodyHeight: CGFloat = 0
    private var currentDistanceStateText: String = "unknown"
    private var currentDistanceFrames: Int = 0
    private var distanceDebugTimer: Timer? = nil
    
    private func handleDistanceGuidance(bodyHeight: CGFloat, distanceState: PoseEstimator.BodyDistance, tooClose: Bool, optimal: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Track current body height
            self.currentBodyHeight = bodyHeight
            
            // Track distance frames and state text for debugging
            let stateText: String
            switch distanceState {
            case .tooClose: stateText = "tooClose"
            case .optimal: stateText = "optimal"
            case .tooFar: stateText = "tooFar"
            case .unknown: stateText = "unknown"
            }
            if stateText == self.currentDistanceStateText {
                self.currentDistanceFrames += 1
            } else {
                self.currentDistanceStateText = stateText
                self.currentDistanceFrames = 1
            }
            
            self.isTooClose = tooClose
            self.isOptimalDistance = optimal
            self.isTooFar = (distanceState == .tooFar)
            
            if tooClose {
                // Overlay message
                // Suppress text-based distance warning in main area per new UX
                // self.feedbackMessage = "Step back to see full body"
                
                // Distance-specific speaking logic:
                // Speak only if tooClose persists 3+ seconds, and only once until user becomes optimal and tooClose again
                if self.isSpeechEnabled {
                    let now = Date()
                    if self.distanceTooCloseStartTime == nil {
                        self.distanceTooCloseStartTime = now
                    }
                    let elapsed = now.timeIntervalSince(self.distanceTooCloseStartTime ?? now)
                    
                    if elapsed >= 3.0 && !self.hasSpokenTooClose {
                        let message = "Please step back"
                        if self.shouldSpeak(message: message) {
                            self.speechManager.speakWorkoutFeedback(message, priority: true)
                            self.hasSpokenTooClose = true
                        }
                    }
                }
            }
            
            if optimal {
                // Optional haptic to confirm optimal distance
                if self.isHapticsEnabled {
                    self.hapticFeedback.impactOccurred(intensity: 0.7)
                }
                // Reset distance speaking gate when optimal is reached
                self.distanceTooCloseStartTime = nil
                self.hasSpokenTooClose = false
                // Clear too far flag when optimal
                self.isTooFar = false
            }
            
            // Debounce UI flicker with a short timer if needed in the future
            self.distanceCheckDebounce?.invalidate()
            self.distanceCheckDebounce = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in }
            
            // Start/refresh a debug timer to print status every 1s
            self.distanceDebugTimer?.invalidate()
            self.distanceDebugTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let sinceSpeech = Date().timeIntervalSince(self.lastSpeechTime)
                let msg = String(format: "Distance Debug - Height: %.2f, State: %@, Frames: %d, Last speech: %.1fs ago", Double(self.currentBodyHeight), self.currentDistanceStateText, self.currentDistanceFrames, sinceSpeech)
                print(msg)
            }
        }
    }
    
    /// Handles pose detection errors
    /// - Parameter error: The pose estimation error
    private func handlePoseDetectionError(_ error: PoseEstimator.PoseEstimationError) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear joint data when pose detection fails
            self.jointPoints.removeAll()
            
            // Update feedback based on error type
            switch error {
            case .noObservationsFound:
                self.feedbackMessage = "Position yourself in camera view"
            case .noValidJointsFound:
                self.feedbackMessage = "Move closer to camera"
            case .invalidPixelBuffer:
                self.feedbackMessage = "Camera error - please restart"
                self.errorMessage = "Camera processing error"
            case .visionRequestFailed:
                self.feedbackMessage = "Pose detection error"
                self.errorMessage = error.localizedDescription
            }
            
            // Reset form metrics
            self.currentKneeAngle = nil
            self.formScore = 0
        }
    }
}

// MARK: - Computed Properties

extension WorkoutViewModel {
    
    /// Camera capture session for preview view
    var captureSession: AVCaptureSession {
        return cameraManager.session
    }
    
    /// Whether camera is currently running
    var isCameraRunning: Bool {
        return cameraManager.isRunning
    }
    
    /// Current workout statistics summary
    var workoutStats: (reps: Int, calories: Double, duration: TimeInterval) {
        return (
            reps: repCount,
            calories: repCounter.getEstimatedCalories(),
            duration: repCounter.getWorkoutDuration()
        )
    }
    
    /// Whether pose is currently being tracked
    var isPoseTracked: Bool {
        return !jointPoints.isEmpty
    }
    
    /// Current rep progress (0.0 to 1.0)
    var repProgress: Double {
        return repCounter.getStateProgress()
    }
}

// MARK: - Debug and Testing Methods

#if DEBUG
extension WorkoutViewModel {
    
    /// Simulates pose detection for testing UI without camera
    /// - Parameter testJoints: Simulated joint positions
    func simulatePoseDetection(testJoints: [String: CGPoint]) {
        processPoseDetection(joints: testJoints)
    }
    
    /// Forces a rep increment for testing
    func debugIncrementRep() {
        repCounter.incrementRep()
    }
    
    /// Gets detailed debug information
    var debugInfo: String {
        return """
        Active: \(isActive)
        Camera: \(isCameraRunning)
        Joints: \(jointPoints.count)
        State: \(currentSquatState.rawValue)
        Angle: \(currentKneeAngle?.description ?? "nil")
        Score: \(formScore)
        """
    }
}
#endif

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLES:
 
 // In your main SwiftUI view
 @StateObject private var workoutViewModel = WorkoutViewModel()
 
 var body: some View {
     ZStack {
         // Camera preview
         CameraPreviewView(session: workoutViewModel.captureSession)
             .ignoresSafeArea()
         
         // Pose overlay
         PoseOverlayView(jointPositions: workoutViewModel.jointPoints)
         
         // UI overlay
         VStack {
             Text("Reps: \(workoutViewModel.repCount)")
             Text(workoutViewModel.feedbackMessage)
             
             Button(workoutViewModel.isActive ? "Stop" : "Start") {
                 workoutViewModel.toggleWorkout()
             }
         }
     }
 }
 
 ...
 
 */
