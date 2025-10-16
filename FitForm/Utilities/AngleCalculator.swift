//
//  AngleCalculator.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Mathematical utilities for pose analysis and joint angle calculations
//

import CoreGraphics
import Foundation

/// Utility class for calculating angles and geometric relationships between body joints
/// Uses vector mathematics for precise angle calculations in pose estimation
struct AngleCalculator {
    
    // MARK: - Angle Calculation
    
    /// Calculates the angle formed by three points using vector dot product method
    /// 
    /// **Mathematical Explanation:**
    /// Given three points A, B, C where B is the vertex (middle point):
    /// 1. Create vectors: BA = A - B, BC = C - B
    /// 2. Calculate dot product: BA · BC = |BA| × |BC| × cos(θ)
    /// 3. Solve for angle: θ = arccos((BA · BC) / (|BA| × |BC|))
    /// 4. Convert from radians to degrees
    ///
    /// - Parameters:
    ///   - point1: First point (e.g., hip in hip-knee-ankle)
    ///   - vertex: Middle point that forms the angle vertex (e.g., knee)
    ///   - point3: Third point (e.g., ankle in hip-knee-ankle)
    /// - Returns: Angle in degrees (0-180), or nil if calculation is invalid
    ///
    /// **Example Usage:**
    /// ```swift
    /// // Calculate knee angle for squat depth analysis
    /// let kneeAngle = AngleCalculator.calculateAngle(
    ///     point1: hipPosition,
    ///     vertex: kneePosition, 
    ///     point3: anklePosition
    /// )
    /// ```
    static func calculateAngle(point1: CGPoint?, vertex: CGPoint?, point3: CGPoint?) -> Double? {
        // Validate input points
        guard let p1 = point1,
              let v = vertex,
              let p3 = point3 else {
            return nil
        }
        
        // Check for degenerate cases (same points)
        guard !arePointsEqual(p1, v) && !arePointsEqual(v, p3) && !arePointsEqual(p1, p3) else {
            return nil
        }
        
        // Create vectors from vertex to the other two points
        // Vector BA = A - B (from vertex to point1)
        let vector1 = CGPoint(x: p1.x - v.x, y: p1.y - v.y)
        
        // Vector BC = C - B (from vertex to point3)  
        let vector2 = CGPoint(x: p3.x - v.x, y: p3.y - v.y)
        
        // Calculate dot product: v1 · v2 = v1.x * v2.x + v1.y * v2.y
        let dotProduct = vector1.x * vector2.x + vector1.y * vector2.y
        
        // Calculate magnitudes (lengths) of vectors
        // |v1| = √(v1.x² + v1.y²)
        let magnitude1 = sqrt(vector1.x * vector1.x + vector1.y * vector1.y)
        let magnitude2 = sqrt(vector2.x * vector2.x + vector2.y * vector2.y)
        
        // Check for zero-length vectors (would cause division by zero)
        guard magnitude1 > 0 && magnitude2 > 0 else {
            return nil
        }
        
        // Calculate cosine of angle: cos(θ) = (v1 · v2) / (|v1| × |v2|)
        let cosineAngle = dotProduct / (magnitude1 * magnitude2)
        
        // Clamp cosine value to valid range [-1, 1] to handle floating point errors
        let clampedCosine = max(-1.0, min(1.0, cosineAngle))
        
        // Calculate angle in radians: θ = arccos(cosine)
        let angleRadians = acos(clampedCosine)
        
        // Convert to degrees: degrees = radians × (180 / π)
        let angleDegrees = angleRadians * 180.0 / .pi
        
        return angleDegrees
    }
    
    // MARK: - Distance Calculations
    
    /// Calculates the Euclidean distance between two points
    ///
    /// **Mathematical Formula:**
    /// distance = √((x₂ - x₁)² + (y₂ - y₁)²)
    ///
    /// - Parameters:
    ///   - point1: First point
    ///   - point2: Second point
    /// - Returns: Distance between points, or nil if either point is nil
    ///
    /// **Example Usage:**
    /// ```swift
    /// // Calculate shoulder width
    /// let shoulderWidth = AngleCalculator.distance(
    ///     between: leftShoulder,
    ///     and: rightShoulder
    /// )
    /// ```
    static func distance(between point1: CGPoint?, and point2: CGPoint?) -> Double? {
        guard let p1 = point1, let p2 = point2 else {
            return nil
        }
        
        // Calculate differences in x and y coordinates
        let deltaX = p2.x - p1.x
        let deltaY = p2.y - p1.y
        
        // Apply Pythagorean theorem: distance = √(Δx² + Δy²)
        let distance = sqrt(deltaX * deltaX + deltaY * deltaY)
        
        return Double(distance)
    }
    
    /// Calculates the normalized distance between two points
    /// Useful when working with normalized coordinates (0-1 range)
    ///
    /// - Parameters:
    ///   - point1: First point (normalized coordinates)
    ///   - point2: Second point (normalized coordinates)
    ///   - viewSize: Size of the view for scaling
    /// - Returns: Distance in view coordinates
    static func normalizedDistance(between point1: CGPoint?, and point2: CGPoint?, viewSize: CGSize) -> Double? {
        guard let distance = distance(between: point1, and: point2) else {
            return nil
        }
        
        // Scale normalized distance to view coordinates
        let averageViewDimension = (viewSize.width + viewSize.height) / 2
        return distance * Double(averageViewDimension)
    }
    
    // MARK: - Midpoint Calculations
    
    /// Calculates the midpoint between two points
    ///
    /// **Mathematical Formula:**
    /// midpoint = ((x₁ + x₂) / 2, (y₁ + y₂) / 2)
    ///
    /// - Parameters:
    ///   - point1: First point
    ///   - point2: Second point
    /// - Returns: Midpoint between the two points, or nil if either point is nil
    ///
    /// **Example Usage:**
    /// ```swift
    /// // Find center point between shoulders
    /// let shoulderCenter = AngleCalculator.midpoint(
    ///     between: leftShoulder,
    ///     and: rightShoulder
    /// )
    /// ```
    static func midpoint(between point1: CGPoint?, and point2: CGPoint?) -> CGPoint? {
        guard let p1 = point1, let p2 = point2 else {
            return nil
        }
        
        // Calculate average of x and y coordinates
        let midX = (p1.x + p2.x) / 2
        let midY = (p1.y + p2.y) / 2
        
        return CGPoint(x: midX, y: midY)
    }
    
    // MARK: - Helper Functions
    
    /// Checks if two points are equal within a small tolerance
    /// Handles floating point precision issues
    ///
    /// - Parameters:
    ///   - point1: First point to compare
    ///   - point2: Second point to compare
    ///   - tolerance: Maximum allowed difference (default: 0.001)
    /// - Returns: True if points are considered equal
    private static func arePointsEqual(_ point1: CGPoint, _ point2: CGPoint, tolerance: CGFloat = 0.001) -> Bool {
        let deltaX = abs(point1.x - point2.x)
        let deltaY = abs(point1.y - point2.y)
        
        return deltaX < tolerance && deltaY < tolerance
    }
}

// MARK: - Pose Analysis Extensions

extension AngleCalculator {
    
    /// Calculates common body angles for fitness pose analysis
    struct PoseAngles {
        
        /// Calculates knee angle for squat depth analysis
        /// - Parameters:
        ///   - hip: Hip joint position
        ///   - knee: Knee joint position  
        ///   - ankle: Ankle joint position
        /// - Returns: Knee angle in degrees (180° = straight leg, <90° = deep squat)
        static func kneeAngle(hip: CGPoint?, knee: CGPoint?, ankle: CGPoint?) -> Double? {
            return AngleCalculator.calculateAngle(point1: hip, vertex: knee, point3: ankle)
        }
        
        /// Calculates elbow angle for push-up or arm exercise analysis
        /// - Parameters:
        ///   - shoulder: Shoulder joint position
        ///   - elbow: Elbow joint position
        ///   - wrist: Wrist joint position  
        /// - Returns: Elbow angle in degrees (180° = straight arm, <90° = bent arm)
        static func elbowAngle(shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?) -> Double? {
            return AngleCalculator.calculateAngle(point1: shoulder, vertex: elbow, point3: wrist)
        }
        
        /// Calculates hip angle for squat or lunge analysis
        /// - Parameters:
        ///   - shoulder: Shoulder joint position (or torso reference)
        ///   - hip: Hip joint position
        ///   - knee: Knee joint position
        /// - Returns: Hip angle in degrees
        static func hipAngle(shoulder: CGPoint?, hip: CGPoint?, knee: CGPoint?) -> Double? {
            return AngleCalculator.calculateAngle(point1: shoulder, vertex: hip, point3: knee)
        }
        
        /// Calculates ankle angle for calf raise or squat analysis
        /// - Parameters:
        ///   - knee: Knee joint position
        ///   - ankle: Ankle joint position
        ///   - toe: Toe position (estimated from ankle if not available)
        /// - Returns: Ankle angle in degrees
        static func ankleAngle(knee: CGPoint?, ankle: CGPoint?, toe: CGPoint?) -> Double? {
            return AngleCalculator.calculateAngle(point1: knee, vertex: ankle, point3: toe)
        }
    }
    
    /// Calculates body alignment and symmetry metrics
    struct BodyAlignment {
        
        /// Checks if shoulders are level (for posture analysis)
        /// - Parameters:
        ///   - leftShoulder: Left shoulder position
        ///   - rightShoulder: Right shoulder position
        /// - Returns: Angle deviation from horizontal in degrees (0° = perfectly level)
        static func shoulderAlignment(leftShoulder: CGPoint?, rightShoulder: CGPoint?) -> Double? {
            guard let left = leftShoulder, let right = rightShoulder else { return nil }
            
            // Calculate angle from horizontal
            let deltaY = right.y - left.y
            let deltaX = right.x - left.x
            
            guard deltaX != 0 else { return 90.0 } // Vertical alignment
            
            let angleRadians = atan(deltaY / deltaX)
            return abs(angleRadians * 180.0 / .pi)
        }
        
        /// Calculates torso lean angle from vertical
        /// - Parameters:
        ///   - shoulder: Shoulder center position
        ///   - hip: Hip center position
        /// - Returns: Lean angle from vertical in degrees (0° = perfectly upright)
        static func torsoLean(shoulder: CGPoint?, hip: CGPoint?) -> Double? {
            guard let shoulderPos = shoulder, let hipPos = hip else { return nil }
            
            // Calculate angle from vertical (straight down)
            let deltaX = shoulderPos.x - hipPos.x
            let deltaY = shoulderPos.y - hipPos.y
            
            guard deltaY != 0 else { return 90.0 } // Horizontal torso
            
            let angleRadians = atan(deltaX / deltaY)
            return abs(angleRadians * 180.0 / .pi)
        }
    }
}

// MARK: - Usage Examples and Documentation

/*
 
 USAGE EXAMPLES:
 
 // Basic angle calculation for squat analysis
 let squatDepth = AngleCalculator.calculateAngle(
     point1: joints["leftHip"],
     vertex: joints["leftKnee"], 
     point3: joints["leftAnkle"]
 )
 
 if let angle = squatDepth {
     if angle < 90 {
         print("Deep squat - excellent form!")
     } else if angle < 120 {
         print("Good squat depth")
     } else {
         print("Squat deeper for better form")
     }
 }
 
 // Distance calculations for body measurements
 let shoulderWidth = AngleCalculator.distance(
     between: joints["leftShoulder"],
     and: joints["rightShoulder"]
 )
 
 // Midpoint calculations for body center
 let torsoCenter = AngleCalculator.midpoint(
     between: joints["leftShoulder"],
     and: joints["rightShoulder"]
 )
 
 // Specialized pose analysis
 let kneeAngle = AngleCalculator.PoseAngles.kneeAngle(
     hip: joints["rightHip"],
     knee: joints["rightKnee"],
     ankle: joints["rightAnkle"]
 )
 
 let shoulderLevel = AngleCalculator.BodyAlignment.shoulderAlignment(
     leftShoulder: joints["leftShoulder"],
     rightShoulder: joints["rightShoulder"]
 )
 
 MATHEMATICAL CONCEPTS:
 
 1. DOT PRODUCT METHOD:
    - More stable than cross product for angle calculation
    - Handles all angle ranges (0° to 180°)
    - Immune to coordinate system orientation
 
 2. VECTOR MATHEMATICS:
    - Vectors represent direction and magnitude
    - Dot product relates to cosine of angle between vectors
    - Formula: A · B = |A| × |B| × cos(θ)
 
 3. EDGE CASE HANDLING:
    - Zero-length vectors (same points)
    - Floating point precision errors
    - Invalid input validation
 
 4. COORDINATE SYSTEMS:
    - Works with any coordinate system (normalized or pixel)
    - Maintains accuracy across different scales
    - Handles both portrait and landscape orientations
 
 */
