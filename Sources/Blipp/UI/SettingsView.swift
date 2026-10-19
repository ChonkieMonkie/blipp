// Blipp, a menu bar sidekick that shows how your Mac is doing.
// Copyright (C) 2026  Anton Gedda
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Preferences

    @StateObject private var login = LoginItem()

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show next to Blipp", selection: $prefs.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                Picker("Style", selection: $prefs.iconStyle) {
                    ForEach(IconStyle.allCases) { style in
                        Label {
                            Text(style.title)
                        } icon: {
                            Image(nsImage: MenuBarIcon.preview(style: style))
                        }
                        .tag(style)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Animate in the menu bar", isOn: $prefs.animateMenuBar)
                Toggle("Mix up animation variants", isOn: $prefs.randomizeVariants)
            }

            Section {
                Picker("Update frequency", selection: $prefs.graphInterval) {
                    ForEach(Preferences.graphIntervals, id: \.self) { interval in
                        Text(Preferences.intervalTitle(interval)).tag(interval)
                    }
                }
                Picker("Time span", selection: $prefs.graphSpan) {
                    ForEach(Preferences.graphSpans, id: \.self) { span in
                        Text(Preferences.spanTitle(span)).tag(span)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Graphs")
            } footer: {
                Text("Applies to every graph in the panel. Faster updates use a little more energy.")
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Picker("Update Blipp every", selection: $prefs.moodInterval) {
                    ForEach(Preferences.moodIntervals, id: \.self) { interval in
                        Text(Preferences.intervalTitle(interval)).tag(interval)
                    }
                }
                Picker("Clicking Blipp", selection: $prefs.clickAction) {
                    ForEach(ClickAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
                Toggle("Launch at login", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                if let launchError = login.error {
                    Text(launchError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Text("Blipp \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Blipp") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Wraps SMAppService so the toggle always reflects what macOS actually did.
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ enable: Bool) {
        let service = SMAppService.mainApp
        do {
            if enable {
                if service.status != .enabled { try service.register() }
            } else if service.status == .enabled {
                try service.unregister()
            }
            error = nil
        } catch {
            self.error = "Couldn't change this: \(error.localizedDescription)"
        }
        enabled = service.status == .enabled
    }
}
