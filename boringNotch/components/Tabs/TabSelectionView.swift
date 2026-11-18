//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

let allTabs = [
    TabModel(label: "Home", icon: "house.fill", view: .home),
    TabModel(label: "Shelf", icon: "tray.fill", view: .shelf),
    TabModel(label: "Focus", icon: "brain.head.profile", view: .focus),
    TabModel(label: "Timer", icon: "timer", view: .timer),
    TabModel(label: "Water", icon: "drop.fill", view: .water),
    TabModel(label: "Rest", icon: "eye.fill", view: .rest),
    TabModel(label: "Prayer", icon: "moon.stars.fill", view: .prayer),
    TabModel(label: "Screen Time", icon: "hourglass", view: .screenTime)
]

/// The tabs shown in the open notch (Shelf only while the shelf is enabled).
var tabs: [TabModel] {
    allTabs.filter { $0.view != .shelf || Defaults[.boringShelf] }
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @Namespace var animation
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view, padding: tabs.count > 7 ? 3 : (tabs.count > 5 ? 5 : (tabs.count > 2 ? 8 : 15))) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    BoringHeader().environmentObject(BoringViewModel())
}
