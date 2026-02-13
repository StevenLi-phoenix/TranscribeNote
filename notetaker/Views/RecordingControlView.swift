//
//  RecordingControlView.swift
//  notetaker
//
//  Created by Steven Li on 2/11/26.
//

import SwiftUI

struct RecordingControlView: View {
    let isRecording: Bool
    let elapsedTime: String
    let onStart: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            if isRecording {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .opacity(pulseAnimation ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseAnimation)
                    .onAppear { pulseAnimation = true }
                    .onDisappear { pulseAnimation = false }
            }

            // Duration display
            Text(elapsedTime)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(isRecording ? .primary : .secondary)

            Spacer()

            // Record/Stop button
            Button {
                if isRecording {
                    onStop()
                } else {
                    onStart()
                }
            } label: {
                Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                    .font(.title)
                    .foregroundStyle(isRecording ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: [.command])
            .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
        }
        .padding()
    }

    @State private var pulseAnimation = false
}
