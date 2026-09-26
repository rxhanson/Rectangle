/// AppSettingsView.swift

import AppKit
import SwiftUI

class AppSettingsViewController: NSViewController {
    private var hostingController: NSHostingController<AppSettingsView>!

    override func viewDidLoad() {
        super.viewDidLoad()

        let swiftUIView = AppSettingsView()
        hostingController = NSHostingController(rootView: swiftUIView)
        
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}

struct AppSettingsView: View {
    @State private var viewModel = AppSettingsViewModel()

    var body: some View {
        Form {
            // MARK: - App & Updates
            Section {
                Toggle("Launch on login", isOn: $viewModel.launchOnLogin)
                Toggle("Hide menu bar icon", isOn: $viewModel.hideMenuBarIcon)

                if viewModel.hideMenuBarIcon {
                    Text("When the menu bar icon is hidden, relaunch Rectangle from Finder to open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                HStack {
                    Button(viewModel.hasPendingUpdate ? "Update Available…" : "Check for Updates…") {
                        viewModel.checkForUpdates()
                    }
                    Spacer()
                    Text(viewModel.versionString)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Toggle("Check for updates automatically", isOn: $viewModel.checkForUpdatesAutomatically)
            }

            Section {
                Toggle("Remove keyboard shortcut restrictions", isOn: $viewModel.allowAnyShortcut)
            }

            // MARK: - Footer Actions
            Section {
                HStack {
                    Button {
                        viewModel.importConfig()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    
                    Button {
                        viewModel.exportConfig()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }

                Button("Restore Default Shortcuts & Snap Areas") {
                    viewModel.restoreDefaults()
                }
                
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }
}
