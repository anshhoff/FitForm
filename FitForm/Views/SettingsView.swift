//
//  SettingsView.swift
//  FitForm
//
//  Created on 10/16/2025.
//  Settings panel for toggling feedback and overlays
//

import SwiftUI

/// Settings screen allowing users to configure feedback preferences
struct SettingsView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    // Bindings to workout view model preferences
    @Binding var isSpeechEnabled: Bool
    @Binding var isSkeletonOverlayEnabled: Bool
    @Binding var isHapticsEnabled: Bool
    @Binding var isSoundEnabled: Bool
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Label("Feedback", systemImage: "speaker.wave.2.fill")) {
                    Toggle(isOn: $isSpeechEnabled) {
                        Label("Voice Feedback", systemImage: "mic.fill")
                    }
                    Toggle(isOn: $isSoundEnabled) {
                        Label("Sound Effects", systemImage: "speaker.wave.2")
                    }
                    Toggle(isOn: $isHapticsEnabled) {
                        Label("Haptic Feedback", systemImage: "hand.point.up.left.fill")
                    }
                }
                
                Section(header: Label("Overlay", systemImage: "viewfinder")) {
                    Toggle(isOn: $isSkeletonOverlayEnabled) {
                        Label("Skeleton Overlay", systemImage: "figure.walk")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Done").bold()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    @State static var speech = true
    @State static var overlay = true
    @State static var haptics = true
    @State static var sound = true
    static var previews: some View {
        SettingsView(
            isSpeechEnabled: $speech,
            isSkeletonOverlayEnabled: $overlay,
            isHapticsEnabled: $haptics,
            isSoundEnabled: $sound
        )
    }
}
#endif


