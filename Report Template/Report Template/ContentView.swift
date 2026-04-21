import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var viewModel = ReportViewModel()
    @StateObject private var appUpdateService = AppUpdateService(owner: "Karlpogi11", repo: "pmg-report")
    @AppStorage("didDismissBackupReminder") private var didDismissBackupReminder = false
    @State private var showingNewReportSheet = false
    @State private var showingSettings = false
    @State private var showingTimeEditor = false
    @State private var showingCopyAlert = false
    @State private var searchText = ""
    @State private var timeEditorValue = Date()
    @State private var copyAlertMessage = "Report copied to clipboard"
    @State private var updateAlert: UpdateAlert?
    
    var filteredHistory: [Report] {
        if searchText.isEmpty {
            return viewModel.history
        }
        return viewModel.history.filter { report in
            report.date.localizedCaseInsensitiveContains(searchText) ||
            report.partsArrived.localizedCaseInsensitiveContains(searchText) ||
            report.mailIn.localizedCaseInsensitiveContains(searchText) ||
            report.formattedOutput.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - History with Search
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search reports...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(10)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                if viewModel.hasHistory && !didDismissBackupReminder {
                    backupReminderBanner
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                
                Divider()
                
                // History List
                if filteredHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: searchText.isEmpty ? "doc.text" : "magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundStyle(.tertiary)
                        Text(searchText.isEmpty ? "No reports yet" : "No results found")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(filteredHistory) { report in
                        Button(action: {
                            viewModel.loadReport(report)
                        }) {
                            HStack(spacing: 12) {
                                // Icon
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.blue.opacity(0.1))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "doc.text.fill")
                                        .foregroundStyle(.blue)
                                }
                                
                                // Content
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(report.date)
                                        .font(.system(.subheadline, design: .rounded))
                                        .fontWeight(.semibold)
                                    Text(report.time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                viewModel.deleteReport(report)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }

                Divider()

                Text("Karl Garcia • 2026")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .frame(minWidth: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 10) {
                        Button(action: copyAllSavedReports) {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                        .disabled(!viewModel.hasHistory)
                        .help("Copy all saved reports as plain text grouped by date")

                        Button(action: { viewModel.exportToExcel() }) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(!viewModel.hasHistory)
                        .help("Export all history to Excel")
                    }
                }
            }
        } detail: {
            // Main content - Modern iOS Style
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        headerCard
                        formCard
                    }
                    .padding(20)
                }
            }
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    HStack(spacing: 12) {
                        Button(action: handleUpdateButtonTap) {
                            Label(updateButtonTitle, systemImage: updateButtonIcon)
                        }
                        .disabled(appUpdateService.isChecking)
                        .help(updateButtonHelpText)
                        
                        Button(action: { showingSettings = true }) {
                            Label("Settings", systemImage: "gearshape")
                        }
                        
                        Button(action: { showingNewReportSheet = true }) {
                            Label("New Report", systemImage: "plus.circle.fill")
                        }
                        .keyboardShortcut("n", modifiers: .command)
                    }
                }
            }
            .sheet(isPresented: $showingNewReportSheet) {
                NewReportSheet(viewModel: viewModel, isPresented: $showingNewReportSheet)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(
                    settings: viewModel.settings,
                    hasHistory: viewModel.hasHistory,
                    onCopyAll: copyAllSavedReports,
                    onExportBackup: { viewModel.exportBackup() },
                    onImportBackup: { viewModel.importBackup() }
                )
            }
            .sheet(isPresented: $showingTimeEditor) {
                TimeEditorSheet(
                    selectedTime: $timeEditorValue,
                    isPresented: $showingTimeEditor,
                    onSave: applyEditedTime
                )
            }
            .alert("Copied!", isPresented: $showingCopyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(copyAlertMessage)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .task {
            _ = await appUpdateService.checkForUpdates()
        }
        .alert(item: $updateAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }
    
    private var updateButtonTitle: String {
        if appUpdateService.isChecking {
            return "Checking..."
        }
        if let version = appUpdateService.availableVersion {
            return "Update \(version)"
        }
        return "Check Update"
    }
    
    private var updateButtonIcon: String {
        if appUpdateService.isChecking {
            return "arrow.triangle.2.circlepath"
        }
        if appUpdateService.availableVersion != nil {
            return "arrow.down.circle"
        }
        return "arrow.triangle.2.circlepath"
    }
    
    private var updateButtonHelpText: String {
        if let version = appUpdateService.availableVersion {
            return "Download and install version \(version)"
        }
        return "Check GitHub releases for a newer version"
    }
    
    private func handleUpdateButtonTap() {
        Task {
            if appUpdateService.availableVersion != nil {
                appUpdateService.openAvailableUpdate()
                return
            }
            
            let result = await appUpdateService.checkForUpdates()
            switch result {
            case .updateAvailable(let release):
                appUpdateService.openAvailableUpdate()
                updateAlert = UpdateAlert(
                    title: "Update Found",
                    message: "Opened installer for version \(release.version). Install over your current app, no uninstall required."
                )
            case .upToDate:
                let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "current"
                updateAlert = UpdateAlert(
                    title: "Up To Date",
                    message: "You are already on version \(current)."
                )
            case .failed(let message):
                updateAlert = UpdateAlert(
                    title: "Update Check Failed",
                    message: message
                )
            case .idle, .checking:
                break
            }
        }
    }
    
    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image("ReportLogo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                    Text("PMG Report")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                if viewModel.hasUnsavedChanges {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                        Text("Saving...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if !viewModel.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 10) {
                Button(action: {
                    viewModel.copyToClipboard()
                    copyAlertMessage = "Report copied to clipboard"
                    showingCopyAlert = true
                }) {
                    Label("Copy", systemImage: "doc.on.clipboard")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(viewModel.isEmpty ? Color.gray : Color.blue)
                        .cornerRadius(10)
                }
                .disabled(viewModel.isEmpty)
                .buttonStyle(.plain)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }

    private var backupReminderBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup your reports")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Deleting the app removes local data. Copy or export your reports before uninstalling.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button(action: { didDismissBackupReminder = true }) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Button("Copy All") {
                    copyAllSavedReports()
                }
                .buttonStyle(.bordered)

                Button("Export Backup") {
                    viewModel.exportBackup()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private var formCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Date and Time Display (Read-only, set from new report sheet)
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DATE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Text(viewModel.currentReport.date)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("TIME")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button(action: openTimeEditor) {
                            Label("Edit", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Text(viewModel.currentReport.time)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(10)
                }
            }
            
            Divider()
            
            // Dynamic Report Sections based on settings
            ForEach(viewModel.settings.fields) { field in
                ModernReportSection(
                    title: field.name,
                    text: binding(for: field.id),
                    icon: field.icon
                )
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(16)
    }
    
    private func binding(for fieldId: String) -> Binding<String> {
        switch fieldId {
        case "partsArrived": return $viewModel.currentReport.partsArrived
        case "mailIn": return $viewModel.currentReport.mailIn
        case "qslReturned": return $viewModel.currentReport.qslReturned
        case "stockIn": return $viewModel.currentReport.stockIn
        case "stockOut": return $viewModel.currentReport.stockOut
        case "safekeeping": return $viewModel.currentReport.safekeeping
        case "kbbShipout": return $viewModel.currentReport.kbbShipout
        case "additionalNotes": return $viewModel.currentReport.additionalNotes
        default: return .constant("")
        }
    }

    private func openTimeEditor() {
        timeEditorValue = parseTime(from: viewModel.currentReport.time) ?? Date()
        showingTimeEditor = true
    }

    private func applyEditedTime(_ time: Date) {
        var report = viewModel.currentReport
        report.time = formatTime(time)
        viewModel.currentReport = report
    }

    private func parseTime(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.date(from: text)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyAllSavedReports() {
        viewModel.copyAllHistoryToClipboardGroupedByDate()
        copyAlertMessage = "All saved reports copied and grouped by date."
        showingCopyAlert = true
        didDismissBackupReminder = true
    }
}

private struct UpdateAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private struct TimeEditorSheet: View {
    @Binding var selectedTime: Date
    @Binding var isPresented: Bool
    let onSave: (Date) -> Void

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Edit Time")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            DatePicker(
                "Time",
                selection: $selectedTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.field)

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    onSave(selectedTime)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}

// MARK: - New Report Sheet

struct NewReportSheet: View {
    @ObservedObject var viewModel: ReportViewModel
    @Binding var isPresented: Bool
    @State private var selectedDate = Date()
    @State private var selectedTime = Date()
    @State private var useCurrentDate = true
    @State private var useCurrentTime = true
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("New Report")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Date Selection
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $useCurrentDate) {
                    Text("Use today's date")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
                
                if !useCurrentDate {
                    DatePicker(
                        "Select Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            // Time Selection
            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $useCurrentTime) {
                    Text("Use current time")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .toggleStyle(.switch)
                
                if !useCurrentTime {
                    DatePicker(
                        "Select Time",
                        selection: $selectedTime,
                        displayedComponents: .hourAndMinute
                    )
                }
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
            
            // Create Button
            Button(action: createNewReport) {
                Text("Create Report")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return)
        }
        .padding(24)
        .frame(width: 450, height: 600)
    }
    
    private func createNewReport() {
        let timeString = useCurrentTime ? formatTime(Date()) : formatTime(selectedTime)
        viewModel.createNewReport(date: useCurrentDate ? Date() : selectedDate, time: timeString)
        isPresented = false
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var settings: ReportSettings
    let hasHistory: Bool
    let onCopyAll: () -> Void
    let onExportBackup: () -> Void
    let onImportBackup: () -> Void
    @Environment(\.dismiss) var dismiss
    @State private var editingField: ReportField?
    @State private var showingAddField = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Fields Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Report Fields")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("Customize the fields that appear in your reports")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        // Fields List
                        VStack(spacing: 8) {
                            ForEach(settings.fields) { field in
                                FieldRow(field: field, settings: settings, editingField: $editingField)
                            }
                            .onMove(perform: settings.moveFields)
                        }
                        
                        // Add Field Button
                        Button(action: { showingAddField = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Field")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(.blue)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Backup & Restore")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Deleting the app removes local data. Copy or export reports before uninstalling.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button(action: onCopyAll) {
                                Label("Copy All", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasHistory)

                            Button(action: onExportBackup) {
                                Label("Export Backup", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasHistory)

                            Button(action: onImportBackup) {
                                Label("Import Backup", systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(20)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(12)
                }
                .padding(20)
            }
        }
        .frame(width: 600, height: 600)
        .sheet(item: $editingField) { field in
            EditFieldSheet(field: field, settings: settings)
        }
        .sheet(isPresented: $showingAddField) {
            AddFieldSheet(settings: settings)
        }
    }
}

// MARK: - Field Row

struct FieldRow: View {
    let field: ReportField
    @ObservedObject var settings: ReportSettings
    @Binding var editingField: ReportField?
    
    var body: some View {
        HStack(spacing: 12) {
            // Drag Handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            
            // Icon
            Image(systemName: field.icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            
            // Name
            Text(field.name)
                .font(.subheadline)
                .fontWeight(.medium)
            
            Spacer()
            
            // Edit Button
            Button(action: { editingField = field }) {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            
            // Delete Button (only for non-core fields)
            if !field.isCore {
                Button(action: { settings.deleteField(field) }) {
                    Image(systemName: "trash.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(8)
    }
}

// MARK: - Edit Field Sheet

struct EditFieldSheet: View {
    let field: ReportField
    @ObservedObject var settings: ReportSettings
    @Environment(\.dismiss) var dismiss
    @State private var fieldName: String
    @State private var selectedIcon: String
    
    init(field: ReportField, settings: ReportSettings) {
        self.field = field
        self.settings = settings
        _fieldName = State(initialValue: field.name)
        _selectedIcon = State(initialValue: field.icon)
    }
    
    let availableIcons = [
        "cube.box.fill", "shippingbox.fill", "envelope.fill", "arrow.turn.up.right",
        "archivebox.fill", "tray.full.fill", "lock.fill", "airplane",
        "doc.text.fill", "note.text", "list.bullet", "checkmark.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Edit Field")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Field Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Field Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., PARTS ARRIVED", text: $fieldName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Icon Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Icon")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(selectedIcon == icon ? Color.blue : Color(nsColor: .controlBackgroundColor))
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer()
            
            // Save Button
            Button(action: saveChanges) {
                Text("Save Changes")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(fieldName.isEmpty)
        }
        .padding(24)
        .frame(width: 450, height: 450)
    }
    
    private func saveChanges() {
        settings.updateField(field, name: fieldName, icon: selectedIcon)
        dismiss()
    }
}

// MARK: - Add Field Sheet

struct AddFieldSheet: View {
    @ObservedObject var settings: ReportSettings
    @Environment(\.dismiss) var dismiss
    @State private var fieldName = ""
    @State private var selectedIcon = "doc.text.fill"
    
    let availableIcons = [
        "cube.box.fill", "shippingbox.fill", "envelope.fill", "arrow.turn.up.right",
        "archivebox.fill", "tray.full.fill", "lock.fill", "airplane",
        "doc.text.fill", "note.text", "list.bullet", "checkmark.circle.fill"
    ]
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Add New Field")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            // Field Name
            VStack(alignment: .leading, spacing: 8) {
                Text("Field Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g., CUSTOM SECTION", text: $fieldName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Icon Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Icon")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(availableIcons, id: \.self) { icon in
                        Button(action: { selectedIcon = icon }) {
                            Image(systemName: icon)
                                .font(.title2)
                                .frame(width: 50, height: 50)
                                .background(selectedIcon == icon ? Color.blue : Color(nsColor: .controlBackgroundColor))
                                .foregroundColor(selectedIcon == icon ? .white : .primary)
                                .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Spacer()
            
            // Add Button
            Button(action: addField) {
                Text("Add Field")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(fieldName.isEmpty ? Color.gray : Color.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(fieldName.isEmpty)
        }
        .padding(24)
        .frame(width: 450, height: 450)
    }
    
    private func addField() {
        settings.addField(name: fieldName, icon: selectedIcon)
        dismiss()
    }
}

// MARK: - Modern Report Section

struct ModernReportSection: View {
    let title: String
    @Binding var text: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(.blue)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
            }
            
            LinkAwareTextEditor(text: $text)
                .frame(minHeight: 100)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(10)
        }
    }
}

private struct LinkAwareTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = LinkAwareNSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.usesFindBar = true
        textView.isAutomaticLinkDetectionEnabled = true
        textView.linkTextAttributes = [
            NSAttributedString.Key.foregroundColor: NSColor.systemBlue,
            NSAttributedString.Key.underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.textContainer?.lineFragmentPadding = 0

        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        textView.string = text
        context.coordinator.applyLinkStyle(in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if context.coordinator.isApplyingStyle {
            return
        }

        if textView.string != text {
            textView.string = text
            context.coordinator.applyLinkStyle(in: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: LinkAwareTextEditor
        var isApplyingStyle = false

        init(_ parent: LinkAwareTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyLinkStyle(in: textView)
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL else { return false }
            NSWorkspace.shared.open(url)
            return true
        }

        func applyLinkStyle(in textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }

            isApplyingStyle = true
            defer { isApplyingStyle = false }

            let selectedRanges = textView.selectedRanges
            let fullRange = NSRange(location: 0, length: textStorage.length)
            let baseFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

            textStorage.beginEditing()
            textStorage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: fullRange)
            textStorage.addAttribute(.font, value: baseFont, range: fullRange)

            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
                detector.enumerateMatches(in: textStorage.string, options: [], range: fullRange) { match, _, _ in
                    guard let match, let url = match.url else { return }
                    textStorage.addAttributes(
                        [
                            .link: url,
                            .foregroundColor: NSColor.systemBlue,
                            .underlineStyle: NSUnderlineStyle.single.rawValue
                        ],
                        range: match.range
                    )
                }
            }

            // Preserve and style any existing pasted hyperlink attributes (rich text links).
            textStorage.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
                guard value != nil else { return }
                textStorage.addAttributes(
                    [
                        .foregroundColor: NSColor.systemBlue,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: range
                )
            }
            textStorage.endEditing()

            textView.selectedRanges = selectedRanges
        }
    }
}

private final class LinkAwareNSTextView: NSTextView {
    override func paste(_ sender: Any?) {
        if let richLinkContent = preferredPastedLinkContent() {
            insertAttributed(richLinkContent)
            return
        }
        super.paste(sender)
    }

    private func preferredPastedLinkContent() -> NSAttributedString? {
        let pasteboard = NSPasteboard.general

        if let attributed = attributedString(from: pasteboard, type: .rtfd, documentType: .rtfd),
           containsLink(in: attributed) {
            return attributed
        }

        if let attributed = attributedString(from: pasteboard, type: .rtf, documentType: .rtf),
           containsLink(in: attributed) {
            return attributed
        }

        if let attributed = attributedString(from: pasteboard, type: .html, documentType: .html),
           containsLink(in: attributed) {
            return attributed
        }

        if let displayText = pasteboard.string(forType: .string),
           !displayText.isEmpty,
           let rawURL = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: NSPasteboard.PasteboardType("public.url")),
           let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let attributed = NSMutableAttributedString(string: displayText)
            attributed.addAttribute(.link, value: url, range: NSRange(location: 0, length: attributed.length))
            return attributed
        }

        return nil
    }

    private func attributedString(
        from pasteboard: NSPasteboard,
        type: NSPasteboard.PasteboardType,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        guard let data = pasteboard.data(forType: type) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
    }

    private func containsLink(in attributed: NSAttributedString) -> Bool {
        var hasLink = false
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.link, in: fullRange, options: []) { value, _, stop in
            if value != nil {
                hasLink = true
                stop.pointee = true
            }
        }
        return hasLink
    }

    private func insertAttributed(_ attributed: NSAttributedString) {
        let range = selectedRange()
        guard shouldChangeText(in: range, replacementString: attributed.string) else { return }
        textStorage?.replaceCharacters(in: range, with: attributed)
        didChangeText()
    }
}

// MARK: - Data Models

struct Report: Identifiable, Codable {
    var id = UUID()
    var date: String
    var time: String
    var partsArrived: String
    var mailIn: String
    var qslReturned: String
    var stockIn: String
    var stockOut: String
    var safekeeping: String
    var kbbShipout: String
    var additionalNotes: String
    var createdAt: Date
    
    init(date: Date = Date(), time: String? = nil) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d, yyyy"
        
        self.id = UUID()
        self.date = dateFormatter.string(from: date)
        self.time = time ?? "8:00 PM"
        self.partsArrived = ""
        self.mailIn = ""
        self.qslReturned = ""
        self.stockIn = ""
        self.stockOut = ""
        self.safekeeping = ""
        self.kbbShipout = ""
        self.additionalNotes = "Checked parts pending, parts inventory"
        self.createdAt = date
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: createdAt)
    }
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
    
    var formattedOutput: String {
        var output = ""
        output += "\(date)\n"
        output += "\(time)\n\n"
        output += "PARTS ARRIVED\n\(partsArrived)\n\n"
        output += "MAIL-IN\n\(mailIn)\n\n"
        output += "QSL RETURNED\n\(qslReturned)\n\n"
        output += "STOCK-IN\n\(stockIn)\n\n"
        output += "STOCK-OUT\n\(stockOut)\n\n"
        output += "SAFEKEEPING\n\(safekeeping)\n\n"
        output += "KBB SHIPOUT\n\(kbbShipout)\n\n"
        output += "OTHERS\n\(additionalNotes)\n"
        return output
    }
    
    var isEmpty: Bool {
        partsArrived.isEmpty &&
        mailIn.isEmpty &&
        qslReturned.isEmpty &&
        stockIn.isEmpty &&
        stockOut.isEmpty &&
        safekeeping.isEmpty &&
        kbbShipout.isEmpty &&
        additionalNotes.isEmpty
    }
}

// MARK: - Report Field Model

struct ReportField: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var icon: String
    var isCore: Bool
    
    static func == (lhs: ReportField, rhs: ReportField) -> Bool {
        lhs.id == rhs.id
    }
}

private struct ReportBackupPackage: Codable {
    var version: Int
    var exportedAt: Date
    var reports: [Report]
    var fields: [ReportField]
}

// MARK: - Report Settings

class ReportSettings: ObservableObject {
    @Published var fields: [ReportField] = []
    
    private let saveKey = "reportSettings"
    
    init() {
        loadSettings()
    }
    
    private func loadSettings() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([ReportField].self, from: data) {
            fields = decoded
        } else {
            // Default fields
            fields = [
                ReportField(id: "partsArrived", name: "PARTS ARRIVED", icon: "cube.box.fill", isCore: true),
                ReportField(id: "mailIn", name: "MAIL-IN", icon: "envelope.fill", isCore: true),
                ReportField(id: "qslReturned", name: "QSL RETURNED", icon: "arrow.turn.up.right", isCore: true),
                ReportField(id: "stockIn", name: "STOCK-IN", icon: "archivebox.fill", isCore: true),
                ReportField(id: "stockOut", name: "STOCK-OUT", icon: "shippingbox.fill", isCore: true),
                ReportField(id: "safekeeping", name: "SAFEKEEPING", icon: "lock.fill", isCore: true),
                ReportField(id: "kbbShipout", name: "KBB SHIPOUT", icon: "airplane", isCore: true),
                ReportField(id: "additionalNotes", name: "ADDITIONAL NOTES", icon: "note.text", isCore: true)
            ]
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(fields) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    func updateField(_ field: ReportField, name: String, icon: String) {
        if let index = fields.firstIndex(where: { $0.id == field.id }) {
            fields[index].name = name
            fields[index].icon = icon
            saveSettings()
        }
    }
    
    func addField(name: String, icon: String) {
        let newField = ReportField(
            id: UUID().uuidString,
            name: name,
            icon: icon,
            isCore: false
        )
        fields.append(newField)
        saveSettings()
    }
    
    func deleteField(_ field: ReportField) {
        fields.removeAll { $0.id == field.id }
        saveSettings()
    }
    
    func moveFields(from source: IndexSet, to destination: Int) {
        fields.move(fromOffsets: source, toOffset: destination)
        saveSettings()
    }

    func replaceFields(with newFields: [ReportField]) {
        guard !newFields.isEmpty else { return }
        fields = newFields
        saveSettings()
    }
}

// MARK: - View Model

@MainActor
class ReportViewModel: ObservableObject {
    @Published var currentReport = Report()
    @Published var history: [Report] = []
    @Published var hasUnsavedChanges = false
    @Published var settings = ReportSettings()
    
    private var autoSaveTimer: Timer?
    private let saveKey = "reportHistory"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadHistory()
        setupAutoSave()
    }
    
    private func setupAutoSave() {
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.hasUnsavedChanges {
                    self.saveCurrentReport()
                }
            }
        }
        
        $currentReport
            .dropFirst()
            .sink { [weak self] _ in
                self?.hasUnsavedChanges = true
            }
            .store(in: &cancellables)
    }
    
    func createNewReport(date: Date, time: String? = nil) {
        saveCurrentReport()
        currentReport = Report(date: date, time: time)
        hasUnsavedChanges = false
    }
    
    func saveCurrentReport() {
        guard !currentReport.isEmpty else {
            hasUnsavedChanges = false
            return
        }
        
        if let index = history.firstIndex(where: { $0.id == currentReport.id }) {
            history[index] = currentReport
        } else {
            history.insert(currentReport, at: 0)
        }
        
        saveHistory()
        hasUnsavedChanges = false
    }
    
    func loadReport(_ report: Report) {
        saveCurrentReport() // Save current before loading another
        currentReport = report
        hasUnsavedChanges = false
    }
    
    func deleteReport(_ report: Report) {
        history.removeAll { $0.id == report.id }
        saveHistory()
    }
    
    func copyToClipboard() {
        let attributedText = makeAttributedReport(from: currentReport.formattedOutput)
        writeToPasteboard(plainText: attributedText.string, attributedText: attributedText)
    }

    func copyAllHistoryToClipboardGroupedByDate() {
        guard !history.isEmpty else { return }

        let attributedText = makeAttributedReport(from: groupedHistoryPlainText())
        writeToPasteboard(plainText: attributedText.string, attributedText: attributedText)
    }

    func exportBackup() {
        guard !history.isEmpty else {
            showModalAlert(
                title: "No Reports to Export",
                message: "Create at least one report before exporting a backup."
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultBackupFileName()
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.writeBackupPackage(to: url)
            }
        }
    }

    func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.readBackupPackage(from: url)
            }
        }
    }
    
    private func makeAttributedReport(from text: String) -> NSAttributedString {
        let attributedText = NSMutableAttributedString(string: text)

        applyMarkdownLinks(to: attributedText)
        applySlackStyleLinks(to: attributedText)
        applyDetectedURLLinks(to: attributedText)

        return attributedText
    }

    private func writeToPasteboard(plainText: String, attributedText: NSAttributedString) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(plainText, forType: .string)

        if let rtfData = try? attributedText.data(
            from: NSRange(location: 0, length: attributedText.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboardItem.setData(rtfData, forType: .rtf)
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([pasteboardItem])
    }

    private func applyMarkdownLinks(to attributedText: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)"#) else {
            return
        }

        while true {
            let fullRange = NSRange(location: 0, length: attributedText.length)
            guard let match = regex.firstMatch(in: attributedText.string, options: [], range: fullRange),
                  match.numberOfRanges == 3 else { return }

            let nsString = attributedText.string as NSString
            let linkText = nsString.substring(with: match.range(at: 1))
            let urlString = nsString.substring(with: match.range(at: 2))

            let replacement = NSMutableAttributedString(string: linkText)
            if let url = URL(string: urlString) {
                replacement.addAttribute(.link, value: url, range: NSRange(location: 0, length: replacement.length))
            }

            attributedText.replaceCharacters(in: match.range, with: replacement)
        }
    }

    private func applySlackStyleLinks(to attributedText: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: #"<(https?://[^>|]+)\|([^>]+)>"#) else {
            return
        }

        while true {
            let fullRange = NSRange(location: 0, length: attributedText.length)
            guard let match = regex.firstMatch(in: attributedText.string, options: [], range: fullRange),
                  match.numberOfRanges == 3 else { return }

            let nsString = attributedText.string as NSString
            let urlString = nsString.substring(with: match.range(at: 1))
            let linkText = nsString.substring(with: match.range(at: 2))

            let replacement = NSMutableAttributedString(string: linkText)
            if let url = URL(string: urlString) {
                replacement.addAttribute(.link, value: url, range: NSRange(location: 0, length: replacement.length))
            }

            attributedText.replaceCharacters(in: match.range, with: replacement)
        }
    }

    private func applyDetectedURLLinks(to attributedText: NSMutableAttributedString) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributedText.length)
        detector.enumerateMatches(in: attributedText.string, options: [], range: fullRange) { match, _, _ in
            guard let match, let link = match.url else { return }
            attributedText.addAttribute(.link, value: link, range: match.range)
        }
    }

    private func groupedHistoryPlainText() -> String {
        let reportsByDate = Dictionary(grouping: history, by: \.date)
        let orderedDates = orderedUniqueDates(from: history)
        let sectionDivider = "\n\n========================================\n\n"

        var sections: [String] = []
        sections.reserveCapacity(orderedDates.count)

        for date in orderedDates {
            guard let reports = reportsByDate[date], !reports.isEmpty else { continue }

            var dateSection = "DATE: \(date)"
            for report in reports {
                let reportBody = report.formattedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                dateSection += "\n\n\(reportBody)"
            }
            sections.append(dateSection)
        }

        return sections.joined(separator: sectionDivider)
    }

    private func orderedUniqueDates(from reports: [Report]) -> [String] {
        var seenDates = Set<String>()
        var orderedDates: [String] = []

        for report in reports {
            if seenDates.insert(report.date).inserted {
                orderedDates.append(report.date)
            }
        }

        return orderedDates
    }

    private func writeBackupPackage(to url: URL) {
        do {
            let payload = ReportBackupPackage(
                version: 1,
                exportedAt: Date(),
                reports: history,
                fields: settings.fields
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: url, options: .atomic)

            showModalAlert(
                title: "Backup Exported",
                message: "Saved \(history.count) reports to \(url.lastPathComponent)."
            )
        } catch {
            showModalAlert(
                title: "Export Failed",
                message: error.localizedDescription,
                style: .critical
            )
        }
    }

    private func readBackupPackage(from url: URL) {
        do {
            let importedPackage = try decodeBackupPackage(from: url)
            guard !importedPackage.reports.isEmpty else {
                showModalAlert(
                    title: "Import Failed",
                    message: "The selected backup file does not contain reports.",
                    style: .warning
                )
                return
            }

            saveCurrentReport()

            guard let importMode = chooseImportMode() else { return }

            switch importMode {
            case .replace:
                history = sortedReports(importedPackage.reports)
                if !importedPackage.fields.isEmpty {
                    settings.replaceFields(with: importedPackage.fields)
                }
            case .merge:
                history = mergedHistory(with: importedPackage.reports)
            }

            saveHistory()
            if let latest = history.first {
                currentReport = latest
            }
            hasUnsavedChanges = false

            showModalAlert(
                title: "Import Successful",
                message: "Imported \(importedPackage.reports.count) report(s)."
            )
        } catch {
            showModalAlert(
                title: "Import Failed",
                message: error.localizedDescription,
                style: .critical
            )
        }
    }

    private func decodeBackupPackage(from url: URL) throws -> ReportBackupPackage {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let payload = try? decoder.decode(ReportBackupPackage.self, from: data) {
            return payload
        }

        let reports = try decoder.decode([Report].self, from: data)
        return ReportBackupPackage(version: 1, exportedAt: Date(), reports: reports, fields: [])
    }

    private enum ImportMode {
        case replace
        case merge
    }

    private func chooseImportMode() -> ImportMode? {
        let alert = NSAlert()
        alert.messageText = "Import Backup"
        alert.informativeText = "Choose how to import reports."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Replace Existing")
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .merge
        default:
            return nil
        }
    }

    private func mergedHistory(with importedReports: [Report]) -> [Report] {
        var mergedByID = Dictionary(uniqueKeysWithValues: history.map { ($0.id, $0) })
        for report in importedReports {
            mergedByID[report.id] = report
        }
        return sortedReports(Array(mergedByID.values))
    }

    private func sortedReports(_ reports: [Report]) -> [Report] {
        reports.sorted { $0.createdAt > $1.createdAt }
    }

    private func defaultBackupFileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "reports_backup_\(formatter.string(from: Date())).json"
    }

    private func showModalAlert(title: String, message: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.runModal()
    }
    
    func exportToExcel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "report_history.csv"

        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.generateCSV(to: url)
            }
        }
    }
    
    private func generateCSV(to url: URL) {
        var csvText = "Date,Time,Parts Arrived,Mail-In,QSL Returned,Stock-In,Stock-Out,Safekeeping,KBB Shipout,Additional Notes\n"
        
        for report in history {
            let row = [
                report.date,
                report.time,
                report.partsArrived.replacingOccurrences(of: "\n", with: " | "),
                report.mailIn.replacingOccurrences(of: "\n", with: " | "),
                report.qslReturned.replacingOccurrences(of: "\n", with: " | "),
                report.stockIn.replacingOccurrences(of: "\n", with: " | "),
                report.stockOut.replacingOccurrences(of: "\n", with: " | "),
                report.safekeeping.replacingOccurrences(of: "\n", with: " | "),
                report.kbbShipout.replacingOccurrences(of: "\n", with: " | "),
                report.additionalNotes.replacingOccurrences(of: "\n", with: " | ")
            ]
            
            let csvRow = row.map { "\"\($0)\"" }.joined(separator: ",")
            csvText += csvRow + "\n"
        }
        
        do {
            try csvText.write(to: url, atomically: true, encoding: .utf8)
            
            // Show success alert
            let alert = NSAlert()
            alert.messageText = "Export Successful"
            alert.informativeText = "History exported to \(url.lastPathComponent)"
            alert.alertStyle = .informational
            alert.runModal()
        } catch {
            // Show error alert
            let alert = NSAlert()
            alert.messageText = "Export Failed"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
        }
    }
    
    var isEmpty: Bool {
        currentReport.isEmpty
    }

    var hasHistory: Bool {
        !history.isEmpty
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: saveKey)
        }
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let decoded = try? JSONDecoder().decode([Report].self, from: data) {
            history = decoded
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
