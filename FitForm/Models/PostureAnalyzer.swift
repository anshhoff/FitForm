//
//  PostureAnalyzer.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Analyzes squat form and provides real-time feedback based on joint positions
//

import CoreGraphics
import Foundation
import Combine

/// Analyzes squat posture and form using joint coordinate data
/// Provides real-time feedback for proper squat technique with intelligent speech management
class PostureAnalyzer: ObservableObject {
    
    // MARK: - Feedback Management Properties
    
    /// Tracks the last feedback message to prevent repetition
    private var lastFeedbackMessage: String = ""
    
    /// Timestamp of the last voice announcement
    private var lastVoiceAnnouncementTime: Date = Date.distantPast
    
    /// Cooldown period between voice announcements (seconds)
    private let voiceCooldownDuration: TimeInterval = 3.0
    
    /// Shared instance for maintaining feedback state across app
    static let shared = PostureAnalyzer()
    
    // MARK: - Initialization
    
    private init() { }
    
    // MARK: - Feedback Categories
    
    /// Categories of feedback messages for different speech handling
    enum FeedbackCategory {
        case positive    // Encouraging messages for good form
        case corrective  // Instructions for form improvements
        case neutral     // General status messages
        
        /// Determines if this category should be spoken immediately
        var shouldSpeak: Bool {
            switch self {
            case .positive:
                return true   // Always speak positive reinforcement
            case .corrective:
                return true   // Always speak corrections for safety
            case .neutral:
                return false  // Don't speak neutral messages to reduce noise
            }
        }
        
        /// Priority level for speech (higher = more important)
        var priority: Int {
            switch self {
            case .corrective: return 3  // Highest priority for safety
            case .positive: return 2    // Medium priority for motivation
            case .neutral: return 1     // Lowest priority
            }
        }
    }
    
    // MARK: - Analysis Thresholds
    
    /// Configurable thresholds for squat form analysis
    /// These values can be adjusted based on user skill level or preferences
    struct SquatThresholds {
        /// Perfect squat knee angle range (degrees)
        /// 70-90° represents optimal squat depth for most individuals
        static let perfectKneeAngleMin: Double = 70.0
        static let perfectKneeAngleMax: Double = 90.0
        
        /// Minimum knee angle for "go lower" feedback (degrees)
        /// Above 90° indicates insufficient squat depth
        static let shallowSquatThreshold: Double = 90.0
        
        /// Maximum back lean angle from vertical (degrees)
        /// Beyond 20° indicates excessive forward lean
        static let maxBackLeanAngle: Double = 20.0
        
        /// Knee-to-toe forward distance threshold (normalized coordinates)
        /// When knee x-position exceeds ankle x-position by this amount,
        /// it indicates knees are tracking too far forward
        static let kneeForwardThreshold: Double = 0.05
        
        /// Minimum confidence threshold for reliable analysis
        /// Only analyze when we have sufficient joint data
        static let minJointsRequired: Int = 6
    }
    
    // MARK: - Analysis Results
    
    /// Comprehensive analysis result for squat form
    struct SquatAnalysis {
        /// Primary feedback message for the user
        let primaryFeedback: String
        
        /// Whether this feedback should be spoken aloud
        let shouldSpeak: Bool
        
        /// Category of the feedback for speech prioritization
        let feedbackCategory: FeedbackCategory
        
        /// Whether this is a new message (different from last)
        let isNewMessage: Bool
        
        /// Detailed breakdown of analysis components
        let kneeAngle: Double?
        let backLeanAngle: Double?
        let kneeForwardDistance: Double?
        
        /// Individual analysis flags
        let hasGoodKneeDepth: Bool
        let hasGoodBackPosture: Bool
        let hasGoodKneeTracking: Bool
        
        /// Overall form quality score (0-100)
        let formScore: Int
        
        /// Additional detailed feedback array
        let detailedFeedback: [String]
    }
    
    // MARK: - Public Analysis Methods
    
    /// Analyzes squat form from joint coordinate data with intelligent feedback management
    /// - Parameter joints: Dictionary of joint names to normalized coordinates (0-1)
    /// - Returns: Comprehensive squat analysis with speech control
    ///
    /// **Required Joints for Analysis:**
    /// - leftHip, rightHip (for hip center calculation)
    /// - leftKnee, rightKnee (for knee angle analysis)
    /// - leftAnkle, rightAnkle (for ankle reference)
    /// - leftShoulder, rightShoulder (for back posture)
    ///
    /// **Speech Management Features:**
    /// - Prevents repeating the same feedback message
    /// - Applies 3-second cooldown between voice announcements
    /// - Categorizes feedback for appropriate speech handling
    /// - Returns shouldSpeak flag for voice synthesis control
    func analyzeSquatForm(joints: [String: CGPoint]) -> SquatAnalysis {
        // Extract required joint positions
        let requiredJoints = PostureAnalyzer.extractRequiredJoints(from: joints)
        
        // Check if we have sufficient data for analysis
        guard requiredJoints.count >= SquatThresholds.minJointsRequired else {
            let feedback = "Position yourself in camera view"
            let (shouldSpeak, isNew) = determineSpeechAction(for: feedback, category: .neutral)
            
            return SquatAnalysis(
                primaryFeedback: feedback,
                shouldSpeak: shouldSpeak,
                feedbackCategory: .neutral,
                isNewMessage: isNew,
                kneeAngle: nil,
                backLeanAngle: nil,
                kneeForwardDistance: nil,
                hasGoodKneeDepth: false,
                hasGoodBackPosture: false,
                hasGoodKneeTracking: false,
                formScore: 0,
                detailedFeedback: ["Not enough joints detected for analysis"]
            )
        }
        
        // Perform individual analysis components
        let kneeAnalysis = PostureAnalyzer.analyzeKneeDepth(joints: requiredJoints)
        let backAnalysis = PostureAnalyzer.analyzeBackPosture(joints: requiredJoints)
        let kneeTrackingAnalysis = PostureAnalyzer.analyzeKneeTracking(joints: requiredJoints)
        
        // Generate comprehensive feedback
        return generateComprehensiveFeedback(
            kneeAnalysis: kneeAnalysis,
            backAnalysis: backAnalysis,
            kneeTrackingAnalysis: kneeTrackingAnalysis
        )
    }
    
    // MARK: - Individual Analysis Components
    
    /// Analyzes knee bend depth using hip-knee-ankle angle
    /// - Parameter joints: Required joint positions
    /// - Returns: Knee analysis result with angle and feedback
    ///
    /// **Analysis Logic:**
    /// - Calculate angle between hip, knee, and ankle
    /// - 180° = straight leg (standing)
    /// - 90° = knee at 90° bend (parallel thigh)
    /// - <90° = deep squat position
    /// - Optimal range: 70-90° for proper squat depth
    private static func analyzeKneeDepth(joints: [String: CGPoint]) -> (angle: Double?, isGood: Bool, feedback: String) {
        // Use average of both legs for more stable analysis
        let leftKneeAngle = AngleCalculator.PoseAngles.kneeAngle(
            hip: joints["leftHip"],
            knee: joints["leftKnee"],
            ankle: joints["leftAnkle"]
        )
        
        let rightKneeAngle = AngleCalculator.PoseAngles.kneeAngle(
            hip: joints["rightHip"],
            knee: joints["rightKnee"],
            ankle: joints["rightAnkle"]
        )
        
        // Calculate average knee angle if both sides are available
        let kneeAngle: Double?
        if let left = leftKneeAngle, let right = rightKneeAngle {
            kneeAngle = (left + right) / 2.0
        } else {
            kneeAngle = leftKneeAngle ?? rightKneeAngle
        }
        
        guard let angle = kneeAngle else {
            return (nil, false, "Cannot detect knee position")
        }
        
        // Analyze knee depth based on angle
        if angle >= SquatThresholds.perfectKneeAngleMin && angle <= SquatThresholds.perfectKneeAngleMax {
            return (angle, true, "Perfect squat depth!")
        } else if angle > SquatThresholds.shallowSquatThreshold {
            return (angle, false, "Go lower - squat deeper")
        } else {
            // Very deep squat (< 70°)
            return (angle, true, "Excellent depth!")
        }
    }
    
    /// Analyzes back straightness using shoulder-hip alignment
    /// - Parameter joints: Required joint positions
    /// - Returns: Back posture analysis with lean angle and feedback
    ///
    /// **Analysis Logic:**
    /// - Calculate center points of shoulders and hips
    /// - Measure angle of shoulder-hip line from vertical
    /// - 0° = perfectly upright posture
    /// - >20° = excessive forward lean (common squat error)
    /// - Slight forward lean (5-15°) is acceptable and natural
    private static func analyzeBackPosture(joints: [String: CGPoint]) -> (angle: Double?, isGood: Bool, feedback: String) {
        // Calculate shoulder and hip center points
        guard let shoulderCenter = AngleCalculator.midpoint(
            between: joints["leftShoulder"],
            and: joints["rightShoulder"]
        ),
        let hipCenter = AngleCalculator.midpoint(
            between: joints["leftHip"],
            and: joints["rightHip"]
        ) else {
            return (nil, false, "Cannot detect torso position")
        }
        
        // Calculate back lean angle from vertical
        let backLeanAngle = AngleCalculator.BodyAlignment.torsoLean(
            shoulder: shoulderCenter,
            hip: hipCenter
        )
        
        guard let angle = backLeanAngle else {
            return (nil, false, "Cannot analyze back posture")
        }
        
        // Analyze back posture based on lean angle
        if angle <= SquatThresholds.maxBackLeanAngle {
            return (angle, true, "Good back posture")
        } else {
            return (angle, false, "Keep back straight - reduce forward lean")
        }
    }
    
    /// Analyzes knee tracking to detect if knees go past toes
    /// - Parameter joints: Required joint positions
    /// - Returns: Knee tracking analysis with distance and feedback
    ///
    /// **Analysis Logic:**
    /// - Compare x-coordinates of knees and ankles
    /// - In proper squat form, knees should not extend significantly past toes
    /// - Ankle position approximates toe position for this analysis
    /// - Excessive forward knee travel can stress knee joints
    private static func analyzeKneeTracking(joints: [String: CGPoint]) -> (distance: Double?, isGood: Bool, feedback: String) {
        // Calculate average knee and ankle positions
        guard let leftKnee = joints["leftKnee"],
              let rightKnee = joints["rightKnee"],
              let leftAnkle = joints["leftAnkle"],
              let rightAnkle = joints["rightAnkle"] else {
            return (nil, false, "Cannot detect knee/ankle positions")
        }
        
        // Calculate average positions for stability
        let avgKneeX = (leftKnee.x + rightKnee.x) / 2.0
        let avgAnkleX = (leftAnkle.x + rightAnkle.x) / 2.0
        
        // Calculate forward distance (positive = knees ahead of ankles)
        let forwardDistance = Double(avgKneeX - avgAnkleX)
        
        // Analyze knee tracking
        if forwardDistance <= SquatThresholds.kneeForwardThreshold {
            return (forwardDistance, true, "Good knee tracking")
        } else {
            return (forwardDistance, false, "Knees too far forward - sit back more")
        }
    }
    
    // MARK: - Helper Methods
    
    /// Extracts and validates required joints for squat analysis
    /// - Parameter joints: All available joint positions
    /// - Returns: Dictionary containing only joints needed for squat analysis
    private static func extractRequiredJoints(from joints: [String: CGPoint]) -> [String: CGPoint] {
        let requiredJointNames = [
            "leftHip", "rightHip",
            "leftKnee", "rightKnee", 
            "leftAnkle", "rightAnkle",
            "leftShoulder", "rightShoulder"
        ]
        
        var requiredJoints: [String: CGPoint] = [:]
        
        for jointName in requiredJointNames {
            if let position = joints[jointName] {
                requiredJoints[jointName] = position
            }
        }
        
        return requiredJoints
    }
    
    /// Generates comprehensive feedback combining all analysis components with speech management
    /// - Parameters:
    ///   - kneeAnalysis: Knee depth analysis results
    ///   - backAnalysis: Back posture analysis results
    ///   - kneeTrackingAnalysis: Knee tracking analysis results
    /// - Returns: Complete squat analysis with speech control and feedback categorization
    private func generateComprehensiveFeedback(
        kneeAnalysis: (angle: Double?, isGood: Bool, feedback: String),
        backAnalysis: (angle: Double?, isGood: Bool, feedback: String),
        kneeTrackingAnalysis: (distance: Double?, isGood: Bool, feedback: String)
    ) -> SquatAnalysis {
        
        // Determine primary feedback based on priority
        let primaryFeedback: String
        let feedbackCategory: FeedbackCategory
        var detailedFeedback: [String] = []
        
        // Priority 1: Back posture (safety first)
        if !backAnalysis.isGood {
            primaryFeedback = categorizeFeedbackMessage(backAnalysis.feedback).message
            feedbackCategory = categorizeFeedbackMessage(backAnalysis.feedback).category
        }
        // Priority 2: Knee tracking (joint safety)
        else if !kneeTrackingAnalysis.isGood {
            primaryFeedback = categorizeFeedbackMessage(kneeTrackingAnalysis.feedback).message
            feedbackCategory = categorizeFeedbackMessage(kneeTrackingAnalysis.feedback).category
        }
        // Priority 3: Knee depth (form optimization)
        else if !kneeAnalysis.isGood {
            primaryFeedback = categorizeFeedbackMessage(kneeAnalysis.feedback).message
            feedbackCategory = categorizeFeedbackMessage(kneeAnalysis.feedback).category
        }
        // All good - perfect form!
        else {
            let perfectFormMessage = selectPositiveFeedback()
            primaryFeedback = perfectFormMessage
            feedbackCategory = .positive
        }
        
        // Determine speech action based on feedback and timing
        let (shouldSpeak, isNewMessage) = determineSpeechAction(for: primaryFeedback, category: feedbackCategory)
        
        // Add detailed feedback for each component
        detailedFeedback.append(kneeAnalysis.feedback)
        detailedFeedback.append(backAnalysis.feedback)
        detailedFeedback.append(kneeTrackingAnalysis.feedback)
        
        // Calculate form score (0-100)
        let goodComponents = [kneeAnalysis.isGood, backAnalysis.isGood, kneeTrackingAnalysis.isGood]
        let score = (goodComponents.filter { $0 }.count * 100) / goodComponents.count
        
        return SquatAnalysis(
            primaryFeedback: primaryFeedback,
            shouldSpeak: shouldSpeak,
            feedbackCategory: feedbackCategory,
            isNewMessage: isNewMessage,
            kneeAngle: kneeAnalysis.angle,
            backLeanAngle: backAnalysis.angle,
            kneeForwardDistance: kneeTrackingAnalysis.distance,
            hasGoodKneeDepth: kneeAnalysis.isGood,
            hasGoodBackPosture: backAnalysis.isGood,
            hasGoodKneeTracking: kneeTrackingAnalysis.isGood,
            formScore: score,
            detailedFeedback: detailedFeedback
        )
    }
    
    // MARK: - Speech Management Helper Methods
    
    /// Determines whether feedback should be spoken based on message novelty and cooldown
    /// - Parameters:
    ///   - message: The feedback message to potentially speak
    ///   - category: The category of the feedback message
    /// - Returns: Tuple of (shouldSpeak: Bool, isNewMessage: Bool)
    private func determineSpeechAction(for message: String, category: FeedbackCategory) -> (shouldSpeak: Bool, isNewMessage: Bool) {
        let currentTime = Date()
        let isNewMessage = message != lastFeedbackMessage
        let isCooldownExpired = currentTime.timeIntervalSince(lastVoiceAnnouncementTime) >= voiceCooldownDuration
        
        // Update last feedback message regardless of speech decision
        lastFeedbackMessage = message
        
        // Determine if we should speak based on category rules and timing
        let shouldSpeak: Bool
        
        switch category {
        case .corrective:
            // Always speak corrective feedback if it's new or cooldown expired
            shouldSpeak = isNewMessage || isCooldownExpired
            
        case .positive:
            // Speak positive feedback only if it's new and cooldown expired
            shouldSpeak = isNewMessage && isCooldownExpired
            
        case .neutral:
            // Rarely speak neutral messages to avoid noise
            shouldSpeak = false
        }
        
        // Update last announcement time if we decide to speak
        if shouldSpeak {
            lastVoiceAnnouncementTime = currentTime
        }
        
        return (shouldSpeak, isNewMessage)
    }
    
    /// Categorizes feedback messages into appropriate speech categories
    /// - Parameter message: The feedback message to categorize
    /// - Returns: Tuple of (message: String, category: FeedbackCategory)
    private func categorizeFeedbackMessage(_ message: String) -> (message: String, category: FeedbackCategory) {
        let lowercaseMessage = message.lowercased()
        
        // Positive feedback patterns
        let positiveKeywords = ["perfect", "great", "excellent", "good", "nice", "well done", "keep it up"]
        if positiveKeywords.contains(where: { lowercaseMessage.contains($0) }) {
            return (message, .positive)
        }
        
        // Corrective feedback patterns
        let correctiveKeywords = ["go lower", "straighten", "back straight", "knees", "forward", "deeper", "sit back"]
        if correctiveKeywords.contains(where: { lowercaseMessage.contains($0) }) {
            return (message, .corrective)
        }
        
        // Default to neutral for unrecognized patterns
        return (message, .neutral)
    }
    
    /// Selects varied positive feedback messages to prevent monotony
    /// - Returns: A positive feedback message
    private func selectPositiveFeedback() -> String {
        let positiveMessages = [
            "Perfect squat form!",
            "Excellent technique!",
            "Great job!",
            "Perfect depth!",
            "Outstanding form!",
            "Keep it up!",
            "Textbook squat!"
        ]
        
        // Use time-based selection to vary messages
        let index = Int(Date().timeIntervalSince1970) % positiveMessages.count
        return positiveMessages[index]
    }
    
    /// Resets feedback tracking (useful for new workout sessions)
    func resetFeedbackTracking() {
        lastFeedbackMessage = ""
        lastVoiceAnnouncementTime = Date.distantPast
    }
}

// MARK: - Extensions for Additional Analysis

extension PostureAnalyzer {
    
    /// Quick analysis method that returns only the primary feedback string
    /// - Parameter joints: Joint coordinate dictionary
    /// - Returns: Simple feedback string for basic UI display
    func getQuickFeedback(joints: [String: CGPoint]) -> String {
        let analysis = analyzeSquatForm(joints: joints)
        return analysis.primaryFeedback
    }
    
    /// Checks if the current pose represents a squat position
    /// - Parameter joints: Joint coordinate dictionary
    /// - Returns: True if person appears to be in squat position
    func isInSquatPosition(joints: [String: CGPoint]) -> Bool {
        let analysis = analyzeSquatForm(joints: joints)
        
        // Consider it a squat if knee angle is less than 120° (some bend)
        guard let kneeAngle = analysis.kneeAngle else { return false }
        return kneeAngle < 120.0
    }
    
    /// Gets form score as a percentage
    /// - Parameter joints: Joint coordinate dictionary
    /// - Returns: Form quality score (0-100)
    func getFormScore(joints: [String: CGPoint]) -> Int {
        let analysis = analyzeSquatForm(joints: joints)
        return analysis.formScore
    }
    
    /// Gets speech-ready feedback with timing control
    /// - Parameter joints: Joint coordinate dictionary
    /// - Returns: Tuple of (feedback: String, shouldSpeak: Bool, category: FeedbackCategory)
    func getSpeechFeedback(joints: [String: CGPoint]) -> (feedback: String, shouldSpeak: Bool, category: FeedbackCategory) {
        let analysis = analyzeSquatForm(joints: joints)
        return (analysis.primaryFeedback, analysis.shouldSpeak, analysis.feedbackCategory)
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLES:
 
 // Basic usage with pose estimation results
 let analysis = PostureAnalyzer.analyzeSquatForm(joints: detectedJoints)
 print(analysis.primaryFeedback) // "Perfect form!" or specific correction
 
 // Quick feedback for simple UI
 let feedback = PostureAnalyzer.getQuickFeedback(joints: detectedJoints)
 feedbackLabel.text = feedback
 
 // Detailed analysis for advanced UI
 let analysis = PostureAnalyzer.analyzeSquatForm(joints: detectedJoints)
 if let kneeAngle = analysis.kneeAngle {
     kneeAngleLabel.text = "Knee Angle: \(Int(kneeAngle))°"
 }
 
 progressBar.progress = Float(analysis.formScore) / 100.0
 
 // Check if user is squatting
 if PostureAnalyzer.isInSquatPosition(joints: detectedJoints) {
     startAnalyzing()
 } else {
     showInstructions("Please perform a squat")
 }
 
 ANALYSIS CRITERIA:
 
 1. KNEE DEPTH (Hip-Knee-Ankle Angle):
    - Perfect: 70-90° (thighs parallel or below)
    - Shallow: >90° (needs to go lower)
    - Excellent: <70° (very deep squat)
 
 2. BACK POSTURE (Shoulder-Hip Alignment):
    - Good: ≤20° lean from vertical
    - Poor: >20° forward lean (excessive)
    - Natural slight lean (5-15°) is acceptable
 
 3. KNEE TRACKING (Knee vs Ankle Position):
    - Good: Knees stay behind or aligned with ankles
    - Poor: Knees extend significantly past ankles
    - Threshold: 0.05 normalized coordinate units
 
 FEEDBACK PRIORITY:
 1. Back posture (safety - prevent injury)
 2. Knee tracking (joint health)
 3. Knee depth (form optimization)
 
 CUSTOMIZATION:
 - Adjust thresholds in SquatThresholds struct
 - Modify for different skill levels
 - Add new analysis components as needed
 
 */

