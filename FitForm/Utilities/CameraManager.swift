//
//  CameraManager.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Camera manager for fitness pose estimation with AVFoundation
//

import AVFoundation
import SwiftUI
import Combine

/// Manages camera capture session for pose estimation
/// Handles front camera setup, frame capture, and permission management
@MainActor
class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    /// Current camera frame as CVPixelBuffer for pose estimation
    @Published var currentFrame: CVPixelBuffer?
    
    /// Camera permission status
    @Published var isAuthorized = false
    
    /// Camera session running status
    @Published var isRunning = false
    
    /// Error messages for UI display
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    /// Main capture session (kept private; expose via read-only accessor below)
    private let captureSession = AVCaptureSession()
    
    /// Front camera device
    private var frontCamera: AVCaptureDevice?
    
    /// Camera input
    private var cameraInput: AVCaptureDeviceInput?
    
    /// Video output for frame capture
    private var videoOutput: AVCaptureVideoDataOutput?
    
    /// Background queue for video processing
    private let videoQueue = DispatchQueue(label: "com.fitform.camera.video", qos: .userInteractive)
    
    /// Session queue for configuration
    private let sessionQueue = DispatchQueue(label: "com.fitform.camera.session", qos: .userInitiated)
    
    // MARK: - Public Read-only Accessors
    
    /// Read-only access to the capture session for preview layers
    var session: AVCaptureSession { captureSession }
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        setupCamera()
    }
    
    // MARK: - Public Methods
    
    /// Requests camera permission and starts capture session
    func start() {
        Task {
            await requestCameraPermission()
            if isAuthorized {
                await startCaptureSession()
            }
        }
    }
    
    /// Stops the capture session
    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                
                DispatchQueue.main.async {
                    self.isRunning = false
                    self.currentFrame = nil
                }
            }
        }
    }
    
    // MARK: - Private Setup Methods
    
    /// Initial camera setup and configuration
    private func setupCamera() {
        sessionQueue.async { [weak self] in
            self?.configureCaptureSession()
        }
    }
    
    /// Configures the complete capture session
    private func configureCaptureSession() {
        // Begin configuration
        captureSession.beginConfiguration()
        
        // Set session preset for high quality
        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        } else {
            captureSession.sessionPreset = .medium
        }
        
        // Setup camera input
        guard setupCameraInput() else {
            captureSession.commitConfiguration()
            DispatchQueue.main.async {
                self.errorMessage = "Failed to setup camera input"
            }
            return
        }
        
        // Setup video output
        guard setupVideoOutput() else {
            captureSession.commitConfiguration()
            DispatchQueue.main.async {
                self.errorMessage = "Failed to setup video output"
            }
            return
        }
        
        // Commit configuration
        captureSession.commitConfiguration()
    }
    
    /// Sets up front camera input
    /// - Returns: Success status
    private func setupCameraInput() -> Bool {
        // Get front camera device
        guard let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            DispatchQueue.main.async {
                self.errorMessage = "Front camera not available"
            }
            return false
        }
        
        self.frontCamera = frontCamera
        
        do {
            // Create camera input
            let cameraInput = try AVCaptureDeviceInput(device: frontCamera)
            
            // Add input to session
            if captureSession.canAddInput(cameraInput) {
                captureSession.addInput(cameraInput)
                self.cameraInput = cameraInput
                return true
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Cannot add camera input to session"
                }
                return false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to create camera input: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    /// Sets up video data output for frame capture
    /// - Returns: Success status
    private func setupVideoOutput() -> Bool {
        let videoOutput = AVCaptureVideoDataOutput()
        
        // Configure video output settings
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        // Set delegate for frame processing
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        // Discard late frames to maintain performance
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Add output to session
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            self.videoOutput = videoOutput
            
            // Configure video connection
            if let connection = videoOutput.connection(with: .video) {
                // Set video orientation
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                
                // Mirror front camera for natural user experience
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = true
                }
            }
            
            return true
        } else {
            DispatchQueue.main.async {
                self.errorMessage = "Cannot add video output to session"
            }
            return false
        }
    }
    
    // MARK: - Permission Handling
    
    /// Requests camera permission from user
    private func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            isAuthorized = true
            
        case .notDetermined:
            // Request permission
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            if !granted {
                errorMessage = "Camera access denied. Please enable camera access in Settings."
            }
            
        case .denied, .restricted:
            isAuthorized = false
            errorMessage = "Camera access denied. Please enable camera access in Settings."
            
        @unknown default:
            isAuthorized = false
            errorMessage = "Unknown camera permission status"
        }
    }
    
    // MARK: - Session Control
    
    /// Starts the capture session on background queue
    private func startCaptureSession() async {
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                    
                    DispatchQueue.main.async {
                        self.isRunning = self.captureSession.isRunning
                        if self.isRunning {
                            self.errorMessage = nil
                        }
                    }
                }
                
                continuation.resume()
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Called when a new video frame is captured
    /// - Parameters:
    ///   - output: The capture output
    ///   - sampleBuffer: The captured sample buffer containing the frame
    ///   - connection: The connection from which the sample buffer was received
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Convert sample buffer to CVPixelBuffer
        guard let pixelBuffer = convertSampleBufferToPixelBuffer(sampleBuffer) else {
            return
        }
        
        // Update current frame on main queue for SwiftUI
        DispatchQueue.main.async { [weak self] in
            self?.currentFrame = pixelBuffer
        }
    }
    
    /// Called when frames are dropped
    /// - Parameters:
    ///   - output: The capture output
    ///   - sampleBuffer: The dropped sample buffer
    ///   - connection: The connection from which the sample buffer was received
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Log dropped frames for debugging
        print("CameraManager: Dropped frame")
    }
    
    // MARK: - Buffer Conversion
    
    /// Converts CMSampleBuffer to CVPixelBuffer for pose estimation
    /// - Parameter sampleBuffer: The sample buffer to convert
    /// - Returns: CVPixelBuffer if conversion successful, nil otherwise
    private func convertSampleBufferToPixelBuffer(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
        // Get image buffer from sample buffer
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        // Return the pixel buffer
        return imageBuffer
    }
}

// MARK: - Error Handling

extension CameraManager {
    
    /// Clears any existing error message
    func clearError() {
        errorMessage = nil
    }
    
    /// Handles camera setup errors
    /// - Parameter error: The error that occurred
    private func handleCameraError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = "Camera error: \(error.localizedDescription)"
            self?.isRunning = false
        }
    }
}
