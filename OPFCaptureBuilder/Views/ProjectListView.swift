//
//  ProjectListView.swift
//  OPFCaptureBuilder
//
//  Lists saved projects with image count and storage size, and offers create / open /
//  rename / duplicate / delete.
//

import SwiftUI

struct ProjectListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingNewProject = false
    @State private var projectToRename: CaptureProject?
    @State private var renameText = ""
    @State private var projectToDelete: CaptureProject?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if model.store.projects.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(model.store.projects) { project in
                            NavigationLink {
                                ProjectDetailView(project: project)
                            } label: {
                                row(project)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    projectToDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    renameText = project.name
                                    projectToRename = project
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(AppTheme.accent)
                            }
                            .contextMenu {
                                Button {
                                    renameText = project.name
                                    projectToRename = project
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button {
                                    duplicate(project)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                Button(role: .destructive) {
                                    projectToDelete = project
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Projects")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("projects.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingNewProject = true
                        } label: {
                            Label("New Project", systemImage: "plus")
                        }
                        Button {
                            createSampleProject()
                        } label: {
                            Label("Create Sample Project", systemImage: "wand.and.stars")
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .accessibilityIdentifier("projects.new")
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectView()
            }
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            .alert("Rename project", isPresented: Binding(
                get: { projectToRename != nil },
                set: { if !$0 { projectToRename = nil } }
            )) {
                TextField("Project name", text: $renameText)
                Button("Cancel", role: .cancel) { projectToRename = nil }
                Button("Rename") { performRename() }
            }
            .confirmationDialog(
                "Delete this project and all its photographs?",
                isPresented: Binding(
                    get: { projectToDelete != nil },
                    set: { if !$0 { projectToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) { projectToDelete = nil }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(AppTheme.accent)
                .accessibilityHidden(true)
            Text("No projects yet")
                .font(.title3.weight(.semibold))
            Text("Create a project to start capturing or importing photographs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingNewProject = true
            } label: {
                Label("New Project", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("projects.empty.new")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.groupedBackground)
    }

    private func row(_ project: CaptureProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            if !project.description.isEmpty {
                Text(project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Label("\(project.images.count) images", systemImage: "photo.on.rectangle")
                Label(ByteCountFormatterHelper.string(model.store.storageSize(of: project)), systemImage: "internaldrive")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("project.row.\(project.name)")
    }

    // MARK: - Actions

    private func createSampleProject() {
        do {
            let project = try SampleProjectFactory.makeSampleProject(store: model.store)
            model.banner = BannerMessage(text: "Sample project created with synthetic data.", kind: .success)
            model.open(project)
        } catch {
            model.banner = BannerMessage(text: error.localizedDescription, kind: .error)
        }
    }

    private func performRename() {        guard let project = projectToRename else { return }
        do {
            _ = try model.store.rename(project, to: renameText)
            model.banner = BannerMessage(text: "Project renamed.", kind: .success)
        } catch {
            model.banner = BannerMessage(text: error.localizedDescription, kind: .error)
        }
        projectToRename = nil
    }

    private func duplicate(_ project: CaptureProject) {
        do {
            _ = try model.store.duplicate(project)
            model.banner = BannerMessage(text: "Project duplicated.", kind: .success)
        } catch {
            model.banner = BannerMessage(text: error.localizedDescription, kind: .error)
        }
    }

    private func performDelete() {
        guard let project = projectToDelete else { return }
        do {
            try model.store.delete(project)
            model.banner = BannerMessage(text: "Project deleted.", kind: .success)
        } catch {
            model.banner = BannerMessage(text: error.localizedDescription, kind: .error)
        }
        projectToDelete = nil
    }
}
