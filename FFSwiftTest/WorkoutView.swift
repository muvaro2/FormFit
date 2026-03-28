import SwiftUI

struct WorkoutView: View {
    let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    @State private var isTracking = false
    @State private var showFeedbackExpanded = false
    
    var body: some View {
        NavigationView {
            ZStack {
                VStack(spacing: 24) {
                    Spacer()
                    
                    // Form Score Circle
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 20)
                            .frame(width: 200, height: 200)
                        
                        Circle()
                            .trim(from: 0, to: 0.92)
                            .stroke(primaryOrange, style: StrokeStyle(lineWidth: 20, lineCap: .round))
                            .frame(width: 200, height: 200)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 8) {
                            Text("92")
                                .font(.system(size: 64, weight: .bold))
                                .foregroundColor(primaryOrange)
                            Text("Form Score")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    }
                    
                    // AI Feedback - Clickable
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(primaryOrange)
                            Text("AI Coach")
                                .font(.headline)
                        }
                        
                        Text("Great depth on your squats! Try to keep your knees aligned with your toes for optimal form.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(2)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFeedbackExpanded = true
                        }
                    }
                    
                    // Live Metrics
                    HStack(spacing: 20) {
                        MetricView(icon: "flame.fill", value: "12", label: "Reps", color: primaryOrange)
                        MetricView(icon: "dumbbell.fill", value: "Biceps", label: "Workout", color: .blue)
                        MetricView(icon: "clock.fill", value: "1:34", label: "Time", color: .blue)
                    }

                    Spacer()

                    // Start/Stop Button
                    Button(action: {
                        isTracking.toggle()
                    }) {
                        Text(isTracking ? "Stop Workout" : "Start Workout")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isTracking ? Color.red : primaryOrange)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal)
                }
                .padding()
                .background(Color(red: 0.97, green: 0.97, blue: 0.97))
                .navigationTitle("Live Workout")
                
                // Expanded Feedback Overlay
                if showFeedbackExpanded {
                    ZStack {
                        Rectangle()
                            .foregroundColor(Color.black.opacity(0.5))
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "sparkles")
                                    .foregroundColor(primaryOrange)
                                    .font(.title2)
                                Text("AI Coach Feedback")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            
                            Text("Great depth on your squats! Try to keep your knees aligned with your toes for optimal form. This will help prevent injury and maximize muscle engagement in your quadriceps and glutes.")
                                .font(.body)
                                .foregroundColor(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("Tap anywhere to close")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 8)
                        }
                        .padding(24)
                        .background(Color.white)
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                        .padding(.horizontal, 40)
                    }
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            showFeedbackExpanded = false
                        }
                    }
                }
            }
        }
    }
}

struct MetricView: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    WorkoutView()
}
