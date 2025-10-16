//
//  RepCounter.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Tracks squat repetitions using state machine for accurate counting
//

import Foundation
import Combine

/// Tracks squat repetitions using a state machine approach
/// Prevents double-counting and ensures complete movement cycles
@MainActor
class RepCounter: ObservableObject {
    
    // MARK: - State Machine Definition
    
    /// Squat repetition states for tracking complete movement cycles
    ///
    /// **STATE MACHINE DIAGRAM:**
    /// ```
    ///     ┌─────────────┐
    ///     │  .standing  │ ◄─────────────────────────────────┐
    ///     │  (>160°)    │                                   │
    ///     └──────┬──────┘                                   │
    ///            │ angle decreases                          │
    ///            ▼                                          │
    ///     ┌─────────────┐                                   │
    ///     │ .descending │                                   │
    ///     │ (160°-90°)  │                                   │
    ///     └──────┬──────┘                                   │
    ///            │ angle < 90°                              │
    ///            ▼                                          │
    ///     ┌─────────────┐                                   │
    ///     │  .bottom    │                                   │
    ///     │  (<90°)     │                                   │
    ///     └──────┬──────┘                                   │
    ///            │ angle increases                          │
    ///            ▼                                          │
    ///     ┌─────────────┐                                   │
    ///     │ .ascending  │                                   │
    ///     │ (90°-160°)  │                                   │
    ///     └──────┬──────┘                                   │
    ///            │ angle > 160° + cooldown                  │
    ///            └──────────────────────────────────────────┘
    ///                         REP COUNTED!
    /// ```
    ///
    /// **State Transitions:**
    /// - Standing → Descending: Knee angle drops below 160°
    /// - Descending → Bottom: Knee angle drops below 90°
    /// - Bottom → Ascending: Knee angle rises above 90°
    /// - Ascending → Standing: Knee angle rises above 160° (with cooldown)
    ///
    /// **Rep Counting Logic:**
    /// A complete repetition is counted only when the full cycle is completed:
    /// Standing → Descending → Bottom → Ascending → Standing
    enum SquatState: String, CaseIterable {
        case standing = "Standing"
        case descending = "Descending"
        case bottom = "Bottom Position"
        case ascending = "Ascending"
        
        /// Human-readable description of the current state
        var description: String {
            switch self {
            case .standing:
                return "Ready to squat"
            case .descending:
                return "Going down"
            case .bottom:
                return "Hold bottom position"
            case .ascending:
                return "Coming up"
            }
        }
    }
    
    // MARK: - Published Properties
    
    /// Current repetition count
    @Published var repCount: Int = 0
    
    /// Current state of the squat movement
    @Published var currentState: SquatState = .standing
    
    /// Current knee angle being tracked
    @Published var currentKneeAngle: Double = 180.0
    
    /// Whether the counter is actively tracking (has valid angle data)
    @Published var isTracking: Bool = false
    
    /// Time remaining in cooldown period (for UI feedback)
    @Published var cooldownRemaining: TimeInterval = 0.0
    
    // MARK: - Configuration Constants
    
    /// Angle thresholds for state transitions
    private struct AngleThresholds {
        /// Angle above which person is considered standing (nearly straight legs)
        static let standingThreshold: Double = 160.0
        
        /// Angle below which person is considered at bottom of squat
        static let bottomThreshold: Double = 90.0
        
        /// Hysteresis buffer to prevent rapid state changes near thresholds
        static let hysteresisBuffer: Double = 5.0
    }
    
    /// Timing configuration
    private struct TimingConfig {
        /// Cooldown period to prevent double-counting (seconds)
        static let cooldownDuration: TimeInterval = 0.5
        
        /// Maximum time without angle updates before stopping tracking
        static let trackingTimeout: TimeInterval = 2.0
    }
    
    // MARK: - Private Properties
    
    /// Last time a rep was counted (for cooldown enforcement)
    private var lastRepTime: Date = Date.distantPast
    
    /// Timer for cooldown countdown display
    private var cooldownTimer: Timer?
    
    /// Timer for tracking timeout
    private var trackingTimer: Timer?
    
    /// Last time angle was updated (for tracking timeout)
    private var lastAngleUpdate: Date = Date()
    
    // MARK: - Initialization
    
    init() {
        // RepCounter is ready to use after initialization
        setupTrackingTimeout()
    }
    
    deinit {
        cooldownTimer?.invalidate()
        trackingTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Updates the rep counter with a new knee angle measurement
    /// - Parameter kneeAngle: Current knee angle in degrees (0-180°)
    ///
    /// **Usage Example:**
    /// ```swift
    /// // In your pose analysis loop
    /// if let angle = analysis.kneeAngle {
    ///     repCounter.updateKneeAngle(angle)
    /// }
    /// ```
    func updateKneeAngle(_ kneeAngle: Double) {
        // Update tracking state
        currentKneeAngle = kneeAngle
        lastAngleUpdate = Date()
        isTracking = true
        
        // Reset tracking timeout
        setupTrackingTimeout()
        
        // Process state machine transition
        processStateTransition(kneeAngle: kneeAngle)
    }
    
    /// Resets the rep counter to initial state
    /// Clears count, resets state, and stops all timers
    func reset() {
        repCount = 0
        currentState = .standing
        currentKneeAngle = 180.0
        isTracking = false
        cooldownRemaining = 0.0
        lastRepTime = Date.distantPast
        
        // Stop timers
        cooldownTimer?.invalidate()
        cooldownTimer = nil
        
        setupTrackingTimeout()
    }
    
    /// Manually increments rep count (for testing or manual adjustment)
    func incrementRep() {
        repCount += 1
        lastRepTime = Date()
        startCooldownTimer()
    }
    
    // MARK: - State Machine Logic
    
    /// Processes state transitions based on current angle and state
    /// - Parameter kneeAngle: Current knee angle measurement
    private func processStateTransition(kneeAngle: Double) {
        let newState = determineNewState(currentAngle: kneeAngle, currentState: currentState)
        
        // Check if state changed
        if newState != currentState {
            let previousState = currentState
            currentState = newState
            
            // Check for completed repetition
            checkForCompletedRep(previousState: previousState, newState: newState)
        }
    }
    
    /// Determines the new state based on current angle and existing state
    /// - Parameters:
    ///   - currentAngle: Current knee angle
    ///   - currentState: Current state of the rep counter
    /// - Returns: New state based on angle thresholds and hysteresis
    private func determineNewState(currentAngle: Double, currentState: SquatState) -> SquatState {
        switch currentState {
        case .standing:
            // Transition to descending when angle drops significantly below standing threshold
            if currentAngle < AngleThresholds.standingThreshold - AngleThresholds.hysteresisBuffer {
                return .descending
            }
            
        case .descending:
            // Transition to bottom when reaching bottom threshold
            if currentAngle < AngleThresholds.bottomThreshold {
                return .bottom
            }
            // Return to standing if angle goes back up significantly
            else if currentAngle > AngleThresholds.standingThreshold {
                return .standing
            }
            
        case .bottom:
            // Transition to ascending when angle rises above bottom threshold
            if currentAngle > AngleThresholds.bottomThreshold + AngleThresholds.hysteresisBuffer {
                return .ascending
            }
            
        case .ascending:
            // Transition to standing when reaching standing threshold (with cooldown check)
            if currentAngle > AngleThresholds.standingThreshold && !isInCooldown() {
                return .standing
            }
            // Return to bottom if angle drops significantly
            else if currentAngle < AngleThresholds.bottomThreshold {
                return .bottom
            }
        }
        
        // No state change
        return currentState
    }
    
    /// Checks if a complete repetition was just completed
    /// - Parameters:
    ///   - previousState: The state we're transitioning from
    ///   - newState: The state we're transitioning to
    private func checkForCompletedRep(previousState: SquatState, newState: SquatState) {
        // Rep is completed when transitioning from ascending to standing
        // This ensures a complete cycle: standing → descending → bottom → ascending → standing
        if previousState == .ascending && newState == .standing {
            completeRep()
        }
    }
    
    /// Completes a repetition by incrementing count and starting cooldown
    private func completeRep() {
        repCount += 1
        lastRepTime = Date()
        startCooldownTimer()
    }
    
    // MARK: - Cooldown Management
    
    /// Checks if currently in cooldown period
    /// - Returns: True if cooldown is active
    private func isInCooldown() -> Bool {
        let timeSinceLastRep = Date().timeIntervalSince(lastRepTime)
        return timeSinceLastRep < TimingConfig.cooldownDuration
    }
    
    /// Starts the cooldown timer for UI feedback
    private func startCooldownTimer() {
        cooldownTimer?.invalidate()
        cooldownRemaining = TimingConfig.cooldownDuration
        
        cooldownTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let elapsed = Date().timeIntervalSince(self.lastRepTime)
            self.cooldownRemaining = max(0, TimingConfig.cooldownDuration - elapsed)
            
            if self.cooldownRemaining <= 0 {
                self.cooldownTimer?.invalidate()
                self.cooldownTimer = nil
            }
        }
    }
    
    // MARK: - Tracking Timeout Management
    
    /// Sets up timeout to stop tracking when no angle updates received
    private func setupTrackingTimeout() {
        trackingTimer?.invalidate()
        
        trackingTimer = Timer.scheduledTimer(withTimeInterval: TimingConfig.trackingTimeout, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let timeSinceUpdate = Date().timeIntervalSince(self.lastAngleUpdate)
            if timeSinceUpdate >= TimingConfig.trackingTimeout {
                self.isTracking = false
                self.currentState = .standing // Reset to neutral state
            }
        }
    }
}

// MARK: - Extensions

extension RepCounter {
    
    /// Gets current state progress as a percentage (for UI animations)
    /// - Returns: Progress value 0.0-1.0 based on current state and angle
    func getStateProgress() -> Double {
        switch currentState {
        case .standing:
            return 0.0
        case .descending:
            // Progress from standing (160°) to bottom (90°)
            let range = AngleThresholds.standingThreshold - AngleThresholds.bottomThreshold
            let progress = (AngleThresholds.standingThreshold - currentKneeAngle) / range
            return max(0.0, min(0.5, progress * 0.5)) // 0.0 to 0.5
        case .bottom:
            return 0.5
        case .ascending:
            // Progress from bottom (90°) to standing (160°)
            let range = AngleThresholds.standingThreshold - AngleThresholds.bottomThreshold
            let progress = (currentKneeAngle - AngleThresholds.bottomThreshold) / range
            return max(0.5, min(1.0, 0.5 + progress * 0.5)) // 0.5 to 1.0
        }
    }
    
    /// Gets estimated calories burned (rough approximation)
    /// - Returns: Estimated calories based on rep count
    func getEstimatedCalories() -> Double {
        // Rough estimate: ~0.5 calories per squat for average person
        return Double(repCount) * 0.5
    }
    
    /// Gets workout duration since first rep
    /// - Returns: Time elapsed since counting started
    func getWorkoutDuration() -> TimeInterval {
        guard repCount > 0 else { return 0 }
        // This is a simplified version - in a real app you'd track start time
        return Double(repCount) * 3.0 // Assume ~3 seconds per rep average
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLES:
 
 // In your SwiftUI view
 @StateObject private var repCounter = RepCounter()
 
 // Update with pose analysis results
 if let kneeAngle = analysis.kneeAngle {
     repCounter.updateKneeAngle(kneeAngle)
 }
 
 // Display in UI
 Text("Reps: \(repCounter.repCount)")
 Text("State: \(repCounter.currentState.rawValue)")
 Text("Angle: \(Int(repCounter.currentKneeAngle))°")
 
 // Progress indicator
 ProgressView(value: repCounter.getStateProgress())
 
 // Reset button
 Button("Reset") {
     repCounter.reset()
 }
 
 STATE MACHINE BEHAVIOR:
 
 1. STANDING (>160°):
    - Initial state and rep completion state
    - Waits for significant angle decrease to start descent
    
 2. DESCENDING (160°-90°):
    - Transitional state going down
    - Can return to standing if movement is aborted
    
 3. BOTTOM (<90°):
    - Deep squat position
    - Must reach this state for valid rep
    
 4. ASCENDING (90°-160°):
    - Transitional state coming up
    - Can return to bottom if movement is incomplete
    
 REP COUNTING RULES:
 
 - Complete cycle required: Standing → Descending → Bottom → Ascending → Standing
 - Cooldown prevents double-counting (0.5 seconds)
 - Hysteresis prevents rapid state changes near thresholds
 - Tracking timeout handles loss of pose detection
 
 INTEGRATION WITH POSE ANALYSIS:
 
 // In your pose detection manager
 let analysis = PostureAnalyzer.analyzeSquatForm(joints: joints)
 if let kneeAngle = analysis.kneeAngle {
     repCounter.updateKneeAngle(kneeAngle)
 }
 
 // React to state changes
 repCounter.$currentState
     .sink { state in
         switch state {
         case .bottom:
             provideFeedback("Hold the bottom position")
         case .standing:
             provideFeedback("Great rep!")
         default:
             break
         }
     }
 
 */
