import SwiftUI

struct OnboardingView: View {
    @ObservedObject var doctorVM: DoctorViewModel
    var onComplete: () -> Void

    @State private var currentStep = 0

    private let steps: [(icon: String, title: String, description: String)] = [
        ("hand.wave.fill", "Welcome to CC Pocket", "Manage your Bridge Server, monitor usage, and connect your mobile device — all from the menu bar."),
        ("stethoscope", "Environment Check", "Let's make sure everything is set up correctly. We'll check for Node.js, CLI tools, and the Bridge service."),
        ("checkmark.seal.fill", "You're All Set!", "Your environment is ready. You can always re-run Doctor from the Doctor tab if needed."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 6) {
                ForEach(0..<steps.count, id: \.self) { index in
                    Capsule()
                        .fill(index <= currentStep ? Color.accentColor : .white.opacity(0.15))
                        .frame(width: index == currentStep ? 20 : 8, height: 4)
                        .animation(.smooth, value: currentStep)
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            if currentStep < 2 {
                // Welcome / Doctor steps
                VStack(spacing: 16) {
                    Image(systemName: steps[currentStep].icon)
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                        .symbolEffect(.bounce, value: currentStep)

                    Text(steps[currentStep].title)
                        .font(.title3.weight(.semibold))

                    Text(steps[currentStep].description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                if currentStep == 1 {
                    // Doctor results inline
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            if doctorVM.isRunning && doctorVM.report == nil {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Running checks…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 12)
                            } else if let report = doctorVM.report {
                                ForEach(report.results) { check in
                                    HStack(spacing: 8) {
                                        Image(systemName: check.statusIcon)
                                            .foregroundStyle(checkColor(check.status))
                                            .font(.caption)

                                        Text(check.name)
                                            .font(.caption.weight(.medium))

                                        Spacer()

                                        Text(check.message)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                if let error = doctorVM.actionError {
                                    Label(error, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                }

                                if let action = doctorVM.actionInProgress {
                                    HStack(spacing: 6) {
                                        ProgressView()
                                            .controlSize(.mini)
                                        Text(action)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                    .frame(maxHeight: 200)
                }

                Spacer()

                // Navigation buttons
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation { currentStep -= 1 }
                        }
                        .buttonStyle(.borderless)
                    }

                    Spacer()

                    if currentStep == 0 {
                        Button("Get Started") {
                            withAnimation { currentStep = 1 }
                            doctorVM.runDoctor()
                        }
                        .buttonStyle(.borderedProminent)
                    } else if currentStep == 1 {
                        Button(doctorVM.allPassed ? "Continue" : "Continue Anyway") {
                            withAnimation { currentStep = 2 }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(doctorVM.isRunning)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)

            } else {
                // Final step
                VStack(spacing: 16) {
                    Image(systemName: steps[2].icon)
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce, value: currentStep)

                    Text(steps[2].title)
                        .font(.title3.weight(.semibold))

                    Text(steps[2].description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)

                Spacer()

                Button("Open CC Pocket") {
                    onComplete()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    private func checkColor(_ status: String) -> Color {
        switch status {
        case "pass": return .green
        case "fail": return .red
        case "warn": return .orange
        default: return .secondary
        }
    }
}
