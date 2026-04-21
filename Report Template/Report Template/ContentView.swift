import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Main Content View

struct ContentView: View {
    @StateObject private var viewModel = ReportViewModel()
    @State private var showingNewReportSheet = false
    @State private var showingSettings = false
    @State private var showingCopyAlert = false
    @State private var searchText = ""
    
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
            }
            .frame(minWidth: 250)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { viewModel.exportToExcel() }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .help("Export all history to Excel")
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
                SettingsView(settings: viewModel.settings)
            }
            .alert("Copied!", isPresented: $showingCopyAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Report copied to clipboard")
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
    }
    
    private var headerCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    Text("Current Report")
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
                    Text("TIME")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
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
            
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 100)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(10)
        }
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
        if !additionalNotes.isEmpty {
            output += "\(additionalNotes)\n"
        }
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
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(currentReport.formattedOutput, forType: .string)
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
