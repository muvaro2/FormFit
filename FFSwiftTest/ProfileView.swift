import SwiftUI

struct ProfileView: View {
    let primaryOrange = Color(red: 1.0, green: 0.42, blue: 0.21)
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Profile Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(primaryOrange.opacity(0.2))
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(primaryOrange)
                        }
                        
                        Text(AppUserDirectory.currentUserName)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Member since \(AppUserDirectory.currentUserMemberSince)")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    
                    // Achievements
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Achievements")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            AchievementBadge(icon: "flame.fill", title: "100 Workouts", color: primaryOrange)
                            AchievementBadge(icon: "star.fill", title: "Perfect Form", color: .yellow)
                            AchievementBadge(icon: "bolt.fill", title: "Streak 30d", color: .blue)
                        }
                    }
                    
                    // Integrations
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Integrations")
                            .font(.headline)
                        
                        IntegrationRow(name: "Apple Watch", icon: "applewatch", isConnected: true, color: primaryOrange)
                        IntegrationRow(name: "HealthKit", icon: "heart.fill", isConnected: true, color: .red)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                    
                    // Settings
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.headline)
                        
                        SettingsRow(icon: "bell.fill", title: "Notifications", color: primaryOrange)
                        SettingsRow(icon: "person.2.fill", title: "Share with Friends", color: .blue)
                        SettingsRow(icon: "questionmark.circle.fill", title: "Help & Support", color: .green)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
                }
                .padding()
            }
            .background(Color(red: 0.97, green: 0.97, blue: 0.97))
            .navigationTitle("Profile")
        }
    }
}

struct AchievementBadge: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 60, height: 60)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
            }
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IntegrationRow: View {
    let name: String
    let icon: String
    let isConnected: Bool
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
            
            Text(name)
                .font(.body)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(isConnected ? "Connected" : "Not Connected")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 8)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title3)
                .frame(width: 30)
            
            Text(title)
                .font(.body)
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
                .font(.caption)
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    ProfileView()
}
