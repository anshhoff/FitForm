//
//  SpeechManager.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Text-to-speech manager for workout coaching and feedback
//

import AVFoundation
import Foundation
import Combine

/// Manages text-to-speech functionality for workout coaching
/// Provides voice feedback for form corrections and rep counting
/// Configured for optimal performance during fitness activities
@MainActor
class SpeechManager: NSObject, ObservableObject {
    
    // MARK: - Singleton Instance
    
    /// Shared singleton instance for app-wide speech management
    /// Ensures consistent audio session configuration and prevents conflicts
    static let shared = SpeechManager()
    
    // MARK: - Private Properties
    
    /// Core speech synthesizer for text-to-speech conversion
    private let speechSynthesizer = AVSpeechSynthesizer()
    
    /// Audio session for managing audio playback during workouts
    private let audioSession = AVAudioSession.sharedInstance()
    
    /// Preferred voice for speech synthesis (English US)
    private var preferredVoice: AVSpeechSynthesisVoice?
    
    /// Flag to track if speech synthesis is currently active
    /// Prevents overlapping speech for better user experience
    @Published private(set) var isSpeaking: Bool = false
    
    /// Queue of pending speech utterances
    /// Allows for queued speech when multiple requests are made
    private var speechQueue: [String] = []
    
    /// Flag to control whether speech is enabled
    /// Allows users to disable voice feedback if desired
    @Published var isSpeechEnabled: Bool = true
    
    // MARK: - Speech Configuration Constants
    
    /// Speech synthesis configuration for optimal workout feedback
    private struct SpeechConfig {
        /// Speech rate (0.0 = slowest, 1.0 = fastest)
        /// 0.5 provides clear, understandable speech during exercise
        static let speechRate: Float = 0.5
        
        /// Speech volume (0.0 = silent, 1.0 = maximum)
        /// Full volume ensures audibility over workout sounds
        static let speechVolume: Float = 1.0
        
        /// Speech pitch multiplier (0.5 = lower, 2.0 = higher)
        /// 1.0 provides natural, clear voice tone
        static let speechPitch: Float = 1.0
        
        /// Pre-utterance delay to ensure audio session is ready
        static let preUtteranceDelay: TimeInterval = 0.1
    }
    
    // MARK: - Initialization
    
    /// Private initializer for singleton pattern
    /// Sets up speech synthesizer delegate and audio session
    private override init() {
        super.init()
        setupSpeechSynthesizer()
        setupAudioSession()
        setupPreferredVoice()
    }
    
    // MARK: - Public Methods
    
    /// Speaks the provided text using text-to-speech synthesis
    /// - Parameter text: The text to be spoken
    ///
    /// **Usage Examples:**
    /// ```swift
    /// SpeechManager.shared.speak("Perfect squat form!")
    /// SpeechManager.shared.speak("Rep \(repCount) completed")
    /// SpeechManager.shared.speak("Keep your back straight")
    /// ```
    ///
    /// **Features:**
    /// - Prevents overlapping speech for clarity
    /// - Configures optimal speech parameters for workout environment
    /// - Handles audio session management automatically
    /// - Provides error handling for synthesis failures
    func speak(_ text: String) {
        // Check if speech is enabled
        guard isSpeechEnabled else {
            print("SpeechManager: Speech is disabled")
            return
        }
        
        // Validate input text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("SpeechManager: Cannot speak empty text")
            return
        }
        
        // Prevent overlapping speech for better user experience
        if isSpeaking {
            // Add to queue for later processing
            speechQueue.append(text)
            print("SpeechManager: Added '\(text)' to speech queue")
            return
        }
        
        // Perform speech synthesis
        performSpeechSynthesis(text: text)
    }
    
    /// Immediately stops current speech synthesis
    /// Useful for interrupting long feedback messages or changing context
    ///
    /// **Usage Examples:**
    /// ```swift
    /// // Stop speech when workout is paused
    /// SpeechManager.shared.stop()
    ///
    /// // Stop speech when switching exercises
    /// SpeechManager.shared.stop()
    /// ```
    func stop() {
        guard isSpeaking else { return }
        
        // Stop current speech synthesis
        speechSynthesizer.stopSpeaking(at: .immediate)
        
        // Clear pending queue
        speechQueue.removeAll()
        
        // Update speaking state
        isSpeaking = false
        
        print("SpeechManager: Speech synthesis stopped")
    }
    
    /// Enables or disables speech synthesis
    /// - Parameter enabled: Whether speech should be enabled
    func setSpeechEnabled(_ enabled: Bool) {
        isSpeechEnabled = enabled
        
        // Stop current speech if disabling
        if !enabled && isSpeaking {
            stop()
        }
        
        print("SpeechManager: Speech \(enabled ? "enabled" : "disabled")")
    }
    
    /// Speaks workout-specific feedback with optimized timing
    /// - Parameter feedback: Workout feedback message
    /// - Parameter priority: Whether to interrupt current speech (default: false)
    func speakWorkoutFeedback(_ feedback: String, priority: Bool = false) {
        // Handle priority speech by stopping current speech
        if priority && isSpeaking {
            stop()
        }
        
        // Add contextual prefix for workout feedback
        let workoutText = "Form check: \(feedback)"
        speak(workoutText)
    }
    
    /// Speaks rep count with celebratory tone
    /// - Parameter count: Current repetition count
    func speakRepCount(_ count: Int) {
        let repText = count == 1 ? "1 rep completed" : "\(count) reps completed"
        speak(repText)
    }
    
    // MARK: - Private Setup Methods
    
    /// Configures the speech synthesizer with delegate and settings
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
        print("SpeechManager: Speech synthesizer configured")
    }
    
    /// Sets up audio session for workout environment
    /// Configures playback category with mix-with-others option
    /// This allows speech to play alongside background music or other apps
    private func setupAudioSession() {
        do {
            // Set audio session category for playback with mixing capability
            // .playback: Optimized for audio playback
            // .mixWithOthers: Allows mixing with other audio (music apps, etc.)
            // .duckOthers: Temporarily reduces other audio volume during speech
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers, .duckOthers]
            )
            
            // Activate the audio session
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            print("SpeechManager: Audio session configured for workout environment")
            
        } catch {
            print("SpeechManager: Failed to configure audio session - \(error.localizedDescription)")
            // Continue without optimal audio session - speech will still work
        }
    }
    
    /// Configures the preferred voice for speech synthesis
    /// Selects high-quality English (US) voice for clear communication
    private func setupPreferredVoice() {
        // Get available voices for English (US)
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        
        // Prefer enhanced quality voices if available
        preferredVoice = availableVoices.first { voice in
            voice.language == "en-US" && voice.quality == .enhanced
        }
        
        // Fallback to any English (US) voice
        if preferredVoice == nil {
            preferredVoice = availableVoices.first { voice in
                voice.language == "en-US"
            }
        }
        
        // Final fallback to system default
        if preferredVoice == nil {
            preferredVoice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        if let voice = preferredVoice {
            print("SpeechManager: Selected voice - \(voice.name) (\(voice.language))")
        } else {
            print("SpeechManager: Warning - No English voice available, using system default")
        }
    }
    
    /// Performs the actual speech synthesis with configured parameters
    /// - Parameter text: Text to synthesize
    private func performSpeechSynthesis(text: String) {
        // Create speech utterance with the provided text
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure speech parameters for workout environment
        utterance.voice = preferredVoice
        utterance.rate = SpeechConfig.speechRate
        utterance.volume = SpeechConfig.speechVolume
        utterance.pitchMultiplier = SpeechConfig.speechPitch
        
        // Add slight pre-utterance delay for audio session preparation
        utterance.preUtteranceDelay = SpeechConfig.preUtteranceDelay
        
        // Update speaking state
        isSpeaking = true
        
        // Perform speech synthesis
        speechSynthesizer.speak(utterance)
        
        print("SpeechManager: Speaking - '\(text)'")
    }
    
    /// Processes the next item in the speech queue
    private func processNextInQueue() {
        guard !speechQueue.isEmpty else { return }
        
        let nextText = speechQueue.removeFirst()
        
        // Small delay before speaking next item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.performSpeechSynthesis(text: nextText)
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SpeechManager: AVSpeechSynthesizerDelegate {
    
    /// Called when speech synthesis starts
    /// - Parameters:
    ///   - synthesizer: The speech synthesizer
    ///   - utterance: The utterance being spoken
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("SpeechManager: Started speaking - '\(utterance.speechString)'")
    }
    
    /// Called when speech synthesis completes successfully
    /// - Parameters:
    ///   - synthesizer: The speech synthesizer
    ///   - utterance: The completed utterance
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("SpeechManager: Finished speaking - '\(utterance.speechString)'")
        
        // Update speaking state
        isSpeaking = false
        
        // Process next item in queue if available
        processNextInQueue()
    }
    
    /// Called when speech synthesis is cancelled
    /// - Parameters:
    ///   - synthesizer: The speech synthesizer
    ///   - utterance: The cancelled utterance
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("SpeechManager: Cancelled speaking - '\(utterance.speechString)'")
        
        // Update speaking state
        isSpeaking = false
        
        // Don't process queue when cancelled (user intentionally stopped)
    }
    
    /// Called when speech synthesis encounters an error
    /// - Parameters:
    ///   - synthesizer: The speech synthesizer
    ///   - utterance: The utterance that failed
    ///   - error: The error that occurred
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFail utterance: AVSpeechUtterance, withError error: Error) {
        print("SpeechManager: Speech synthesis failed - \(error.localizedDescription)")
        
        // Update speaking state
        isSpeaking = false
        
        // Continue with queue processing despite error
        processNextInQueue()
    }
}

// MARK: - Convenience Extensions

extension SpeechManager {
    
    /// Speaks common workout phrases with predefined messages
    enum WorkoutPhrase: String, CaseIterable {
        case start = "Workout started. Let's begin!"
        case stop = "Workout completed. Great job!"
        case perfectForm = "Perfect form! Keep it up!"
        case goLower = "Go lower for better depth"
        case keepBackStraight = "Keep your back straight"
        case kneesTooForward = "Don't let your knees go past your toes"
        case goodRep = "Good rep!"
        case excellentDepth = "Excellent squat depth!"
        
        /// Speaks this workout phrase
        func speak() {
            SpeechManager.shared.speak(self.rawValue)
        }
    }
    
    /// Speaks a predefined workout phrase
    /// - Parameter phrase: The workout phrase to speak
    func speak(_ phrase: WorkoutPhrase) {
        speak(phrase.rawValue)
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLES:
 
 // Basic speech synthesis
 SpeechManager.shared.speak("Welcome to your workout!")
 
 // Workout-specific feedback
 SpeechManager.shared.speakWorkoutFeedback("Keep your back straight")
 
 // Rep counting
 SpeechManager.shared.speakRepCount(5)
 
 // Priority speech (interrupts current speech)
 SpeechManager.shared.speakWorkoutFeedback("Stop immediately!", priority: true)
 
 // Predefined workout phrases
 SpeechManager.WorkoutPhrase.perfectForm.speak()
 SpeechManager.shared.speak(.start)
 
 // Control speech functionality
 SpeechManager.shared.setSpeechEnabled(false)
 SpeechManager.shared.stop()
 
 INTEGRATION WITH WORKOUT FLOW:
 
 // In WorkoutViewModel
 class WorkoutViewModel: ObservableObject {
     private let speechManager = SpeechManager.shared
     
     func startWorkout() {
         speechManager.speak(.start)
     }
     
     func handleFormFeedback(_ feedback: String) {
         speechManager.speakWorkoutFeedback(feedback)
     }
     
     func handleRepCompletion(_ count: Int) {
         speechManager.speakRepCount(count)
     }
 }
 
 AUDIO SESSION BENEFITS:
 
 - .playback category: Optimized for speech playback
 - .mixWithOthers: Works with background music apps
 - .duckOthers: Temporarily lowers other audio during speech
 - Workout-friendly: Doesn't interrupt user's music
 
 PERFORMANCE CONSIDERATIONS:
 
 - Singleton pattern prevents multiple instances
 - Queue system handles rapid speech requests
 - @MainActor ensures thread safety
 - Efficient voice caching and reuse
 - Minimal audio session overhead
 
 ERROR HANDLING:
 
 - Graceful fallback for missing voices
 - Audio session configuration errors handled
 - Speech synthesis errors logged and recovered
 - Queue continues processing despite individual failures
 
 */

