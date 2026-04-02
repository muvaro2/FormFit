//
//  FormFitWatchApp.swift
//  FormFitWatch Watch App
//
//  Created by Saavan Kiran on 10/4/25.
//

import SwiftUI

@main
struct FormFitWatch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            CollectorContentView()
                .onAppear {
                    WatchConnectivityManager.shared.activate()
                }
                .preferredColorScheme(.light)
        }
    }
}
