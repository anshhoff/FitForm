//
//  PoseEstimator.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Human body pose estimation using Vision framework
//

import Vision
import CoreVideo
import CoreGraphics
import Foundation

/// Human body pose estimator using Apple's Vision framework
/// Detects and extracts body joint positions from camera frames
class PoseEstimator {
    
    // MARK: - Types
    
    /// Dictionary type for joint positions (joint name -> normalized coordinates)
    typealias JointPositions = [String: CGPoint]
    
    /// Body distance classification
    enum BodyDistance {
        case tooClose
        case optimal
        case tooFar
        case unknown
    }

    /// Result payload including joints and distance flags
    struct PoseResult {
        let joints: JointPositions
        let bodyHeight: CGFloat             // vertical span head->feet in normalized coords (Y-axis only)
        let bodyDistance: BodyDistance      // distance classification
        // Back-compat convenience flags (deprecated)
        let bodyTooClose: Bool
        let bodyOptimalDistance: Bool
    }
    
    /// Completion handler for pose estimation results
    typealias PoseEstimationCompletion = (Result<PoseResult, PoseEstimationError>) -> Void
    
    /// Custom errors for pose estimation
    enum PoseEstimationError: LocalizedError {
        case noObservationsFound
        case visionRequestFailed(Error)
        case invalidPixelBuffer
        case noValidJointsFound
        
        var errorDescription: String? {
            switch self {
            case .noObservationsFound:
                return "No human body pose observations found in the image"
            case .visionRequestFailed(let error):
                return "Vision request failed: \(error.localizedDescription)"
            case .invalidPixelBuffer:
                return "Invalid pixel buffer provided for pose estimation"
            case .noValidJointsFound:
                return "No valid joints found above confidence threshold"
            }
        }
    }
    
    // MARK: - Properties
    
    /// Confidence threshold for joint detection (0.0 to 1.0)
    /// Joints with confidence below this threshold will be filtered out
    private let confidenceThreshold: Float = 0.3
    
    /// Background queue for Vision processing to avoid blocking main thread
    private let processingQueue = DispatchQueue(label: "com.fitform.pose.processing", qos: .userInteractive)
    
    /// Vision request for human body pose detection
    /// Configured once and reused for performance
    private lazy var poseRequest: VNDetectHumanBodyPoseRequest = {
        let request = VNDetectHumanBodyPoseRequest()
        
        // Configure request properties for optimal performance
        request.revision = VNDetectHumanBodyPoseRequestRevision1
        
        return request
    }()
    
    // MARK: - Distance Smoothing State
    
    /// Counts consecutive frames with sufficient body confidence
    private var consecutiveHighConfidenceFrames: Int = 0
    
    /// Last classified body distance
    private var lastDistanceClassification: BodyDistance = .unknown
    
    /// Mapping of Vision joint names to our standardized joint names
    /// Vision uses specific identifiers that we map to more readable names
    private let jointNameMapping: [VNHumanBodyPoseObservation.JointName: String] = [
        .leftShoulder: "leftShoulder",
        .rightShoulder: "rightShoulder",
        .leftHip: "leftHip",
        .rightHip: "rightHip",
        .leftKnee: "leftKnee",
        .rightKnee: "rightKnee",
        .leftAnkle: "leftAnkle",
        .rightAnkle: "rightAnkle",
        .leftElbow: "leftElbow",
        .rightElbow: "rightElbow",
        .leftWrist: "leftWrist",
        .rightWrist: "rightWrist",
        .neck: "neck",
        .nose: "nose"
    ]
    
    // MARK: - Initialization
    
    /// Initialize the pose estimator
    init() {
        // Pose estimator is ready to use after initialization
    }
    
    // MARK: - Public Methods
    
    /// Estimates human body pose from a pixel buffer
    /// - Parameters:
    ///   - pixelBuffer: The CVPixelBuffer containing the image to analyze
    ///   - completion: Completion handler called with the results
    func estimatePose(from pixelBuffer: CVPixelBuffer, completion: @escaping PoseEstimationCompletion) {
        // Validate input pixel buffer
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) != 0 else {
            DispatchQueue.main.async {
                completion(.failure(.invalidPixelBuffer))
            }
            return
        }
        
        // Process on background queue to avoid blocking UI
        processingQueue.async { [weak self] in
            self?.performPoseDetection(on: pixelBuffer, completion: completion)
        }
    }
    
    // MARK: - Private Methods
    
    /// Performs the actual pose detection using Vision framework
    /// - Parameters:
    ///   - pixelBuffer: The pixel buffer to analyze
    ///   - completion: Completion handler for results
    private func performPoseDetection(on pixelBuffer: CVPixelBuffer, completion: @escaping PoseEstimationCompletion) {
        // Create Vision image request handler
        // This handles the conversion from CVPixelBuffer to Vision's internal format
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        
        do {
            // Perform the Vision request
            // This is where the actual ML inference happens
            try requestHandler.perform([poseRequest])
            
            // Process the results
            processVisionResults(completion: completion)
            
        } catch {
            // Handle Vision framework errors
            DispatchQueue.main.async {
                completion(.failure(.visionRequestFailed(error)))
            }
        }
    }
    
    /// Processes Vision framework results and extracts joint positions
    /// - Parameter completion: Completion handler for results
    private func processVisionResults(completion: @escaping PoseEstimationCompletion) {
        // Get the pose observations from the Vision request
        guard let observations = poseRequest.results as? [VNHumanBodyPoseObservation],
              let firstObservation = observations.first else {
            DispatchQueue.main.async {
                completion(.failure(.noObservationsFound))
            }
            return
        }
        
        // Extract joint positions from the observation
        let jointPositions = extractJointPositions(from: firstObservation)
        
        // Check if we found any valid joints
        if jointPositions.isEmpty {
            DispatchQueue.main.async {
                completion(.failure(.noValidJointsFound))
            }
        } else {
            // Compute body height (vertical span) and confidence
            let bodyHeight = computeBodyVerticalSpan(joints: jointPositions)
            let bodyConfidence = computeBodyConfidence(observation: firstObservation)
            print("PoseEstimator: bodyHeight=\(String(format: "%.3f", bodyHeight)) confidence=\(String(format: "%.2f", bodyConfidence))")

            // Update smoothing counter
            if bodyConfidence > 0.6 {
                consecutiveHighConfidenceFrames += 1
            } else {
                consecutiveHighConfidenceFrames = 0
            }

            // Classify distance with thresholds and smoothing requirement
            var distance: BodyDistance = .unknown
            if consecutiveHighConfidenceFrames >= 10 {
                if bodyHeight < 0.4 {
                    distance = .tooClose
                } else if bodyHeight < 0.75 {
                    distance = .optimal
                } else {
                    distance = .tooFar
                }
            } else {
                distance = .unknown
            }
            lastDistanceClassification = distance

            let result = PoseResult(
                joints: jointPositions,
                bodyHeight: bodyHeight,
                bodyDistance: distance,
                bodyTooClose: distance == .tooClose,
                bodyOptimalDistance: distance == .optimal
            )
            
            // Return successful results on main queue
            DispatchQueue.main.async {
                completion(.success(result))
            }
        }
    }
    
    /// Extracts joint positions from a Vision pose observation
    /// - Parameter observation: The VNHumanBodyPoseObservation to process
    /// - Returns: Dictionary of joint names to normalized coordinates
    private func extractJointPositions(from observation: VNHumanBodyPoseObservation) -> JointPositions {
        var jointPositions: JointPositions = [:]
        
        // Iterate through all the joints we're interested in
        for (visionJointName, standardJointName) in jointNameMapping {
            do {
                // Try to get the recognized point for this joint
                // This may fail if the joint wasn't detected or has low confidence
                let recognizedPoint = try observation.recognizedPoint(visionJointName)
                
                // Check if the joint meets our confidence threshold
                // Vision returns confidence as a Float between 0.0 and 1.0
                if recognizedPoint.confidence >= confidenceThreshold {
                    // Convert Vision's coordinate system to standard CGPoint
                    // Vision uses normalized coordinates (0-1) with origin at bottom-left
                    // We convert to standard coordinates with origin at top-left
                    let normalizedPoint = CGPoint(
                        x: recognizedPoint.location.x,
                        y: 1.0 - recognizedPoint.location.y  // Flip Y coordinate
                    )
                    
                    jointPositions[standardJointName] = normalizedPoint
                }
                
            } catch {
                // Joint not found or other error - skip this joint
                // This is normal behavior as not all joints may be visible
                continue
            }
        }
        
        return jointPositions
    }
    
    /// Computes the vertical span (head to feet) using available joints
    /// - Parameter joints: Detected joint positions (normalized coordinates)
    /// - Returns: Span value in range [0, 1] where larger means taller on screen
    private func computeBodyVerticalSpan(joints: JointPositions) -> CGFloat {
        // Prefer nose (head) and ankles (feet). If missing, fall back to min/max Y across all joints
        let headCandidates = ["nose", "neck"]
        let feetCandidates = ["leftAnkle", "rightAnkle", "leftKnee", "rightKnee"]
        
        var minY: CGFloat? = nil
        var maxY: CGFloat? = nil
        
        // Try preferred head/feet points first
        let headY = headCandidates.compactMap { joints[$0]?.y }.min()
        let feetY = feetCandidates.compactMap { joints[$0]?.y }.max()
        
        if let headY = headY, let feetY = feetY {
            minY = headY
            maxY = feetY
        } else {
            // Fallback: use overall min/max across detected joints
            for (_, p) in joints {
                if minY == nil || p.y < minY! { minY = p.y }
                if maxY == nil || p.y > maxY! { maxY = p.y }
            }
        }
        
        guard let top = minY, let bottom = maxY else { return 0 }
        let span = max(0, min(1, bottom - top))
        return span
    }
    
    /// Computes an aggregate body confidence from key joints (nose/neck and ankles)
    /// Falls back to averaging confidences of available mapped joints
    private func computeBodyConfidence(observation: VNHumanBodyPoseObservation) -> Float {
        var confidences: [Float] = []
        let keyJointPrefs: [[VNHumanBodyPoseObservation.JointName]] = [
            [.nose, .neck],
            [.leftAnkle, .rightAnkle]
        ]
        
        // Try preferred groups first
        for group in keyJointPrefs {
            for j in group {
                if let pt = try? observation.recognizedPoint(j) {
                    confidences.append(pt.confidence)
                }
            }
        }
        
        // If insufficient, average over all mapped joints we can read
        if confidences.count < 2 {
            for (j, _) in jointNameMapping {
                if let pt = try? observation.recognizedPoint(j) {
                    confidences.append(pt.confidence)
                }
            }
        }
        
        guard !confidences.isEmpty else { return 0 }
        let sum = confidences.reduce(0, +)
        return sum / Float(confidences.count)
    }
}

// MARK: - Extensions

extension PoseEstimator {
    
    /// Updates the confidence threshold for joint detection
    /// - Parameter threshold: New threshold value (0.0 to 1.0)
    func setConfidenceThreshold(_ threshold: Float) {
        // Note: This would require making confidenceThreshold mutable
        // For now, it's set as a constant for consistency
        print("Confidence threshold update requested: \(threshold)")
        print("Current implementation uses fixed threshold of \(confidenceThreshold)")
    }
    
    /// Gets information about available joints
    /// - Returns: Array of joint names that can be detected
    func getAvailableJoints() -> [String] {
        return Array(jointNameMapping.values).sorted()
    }
    
    /// Checks if a specific joint is supported
    /// - Parameter jointName: Name of the joint to check
    /// - Returns: True if the joint is supported
    func isJointSupported(_ jointName: String) -> Bool {
        return jointNameMapping.values.contains(jointName)
    }
}

// MARK: - Utility Extensions

extension CGPoint {
    
    /// Converts normalized coordinates (0-1) to pixel coordinates
    /// - Parameter imageSize: Size of the image in pixels
    /// - Returns: Point in pixel coordinates
    func toPixelCoordinates(imageSize: CGSize) -> CGPoint {
        return CGPoint(
            x: self.x * imageSize.width,
            y: self.y * imageSize.height
        )
    }
    
    /// Creates a point from normalized coordinates with validation
    /// - Parameters:
    ///   - x: X coordinate (0-1)
    ///   - y: Y coordinate (0-1)
    /// - Returns: Validated CGPoint or nil if coordinates are invalid
    static func normalizedPoint(x: CGFloat, y: CGFloat) -> CGPoint? {
        guard x >= 0 && x <= 1 && y >= 0 && y <= 1 else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLE:
 
 class PoseDetectionManager: ObservableObject {
     private let poseEstimator = PoseEstimator()
     @Published var detectedJoints: [String: CGPoint] = [:]
     @Published var isProcessing = false
     
     func processFrame(_ pixelBuffer: CVPixelBuffer) {
         isProcessing = true
         
         poseEstimator.estimatePose(from: pixelBuffer) { [weak self] result in
             self?.isProcessing = false
             
             switch result {
             case .success(let joints):
                 self?.detectedJoints = joints
                 print("Detected \(joints.count) joints")
                 
                 // Example: Check if person is standing straight
                 if let leftShoulder = joints["leftShoulder"],
                    let rightShoulder = joints["rightShoulder"] {
                     let shoulderAlignment = abs(leftShoulder.y - rightShoulder.y)
                     print("Shoulder alignment: \(shoulderAlignment)")
                 }
                 
             case .failure(let error):
                 print("Pose estimation failed: \(error.localizedDescription)")
             }
         }
     }
 }
 
 COORDINATE SYSTEM:
 - All coordinates are normalized (0.0 to 1.0)
 - Origin (0,0) is at top-left corner
 - X increases to the right
 - Y increases downward
 - Point (1,1) is at bottom-right corner
 
 CONFIDENCE FILTERING:
 - Only joints with confidence > 0.3 are included
 - Higher confidence = more reliable detection
 - Confidence threshold can be adjusted based on use case
 
 PERFORMANCE NOTES:
 - Processing runs on background queue
 - Results delivered on main queue for UI updates
 - Vision request is reused for efficiency
 - Typical processing time: 10-50ms per frame
 
 */
