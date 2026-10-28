import SwiftUI
import MapKit
import AppKit

@MainActor
struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Search, click the map, or enter coordinates"

    @State private var searchQuery = ""
    @State private var isSearching = false
    @State private var isCheckingDevices = false



    // Changing this requests centering on the selected location.
    @State private var mapFocusRequest = UUID()

    // Discovery is a snapshot, not continuous connection monitoring.
    @State private var discoveredDevices: [ConnectedDevice] = []
    @State private var lastDeviceCheck: Date?

    let deviceConnection: DeviceConnection

    // MARK: - Shared session state

    private var hasSimulationSession: Bool {
        switch deviceConnection.state {
        case .running, .stopping, .cleanupRequired:
            return true
        default:
            return false
        }
    }

    private var isStopping: Bool {
        deviceConnection.state == .stopping
    }
    
    private var isStarting: Bool {
        deviceConnection.state == .starting
    }
    
    private var sessionStatus: String {
        if isStarting {
            return "Checking device…"
        }

        return deviceConnection.state.title
    }

    private var backendControlsDisabled: Bool {
        hasSimulationSession ||
        deviceConnection.state.isBusy ||
        isStarting ||
        isCheckingDevices
    }

    // MARK: - Selected location

    private var selectedCoordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude),
              let lon = Double(longitude),
              lat.isFinite,
              lon.isFinite,
              (-90...90).contains(lat),
              (-180...180).contains(lon) else {
            return nil
        }

        return CLLocationCoordinate2D(
            latitude: lat,
            longitude: lon
        )
    }

    // MARK: - Main layout

    var body: some View {
        ZStack(alignment: .leading) {
            locationMap

            sidebar
                .padding(16)
        }
        .frame(minWidth: 900, minHeight: 660)
        .onChange(
            of: deviceConnection.state,
            initial: true
        ) { _, newState in
            // The backend owns session transitions.
            // The view only displays their recovery or failure messages.
            switch newState {
            case .cleanupRequired(let message):
                status = message

            case .failed(let message):
                status = "Couldn't start: \(message)"

            default:
                break
            }
        }
    }

    // MARK: - Glass sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader
                .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    searchControls

                    Divider()

                    coordinateFields

                    Button {
                        centerOnSelection()
                    } label: {
                        Label(
                            "Center on selection",
                            systemImage: "scope"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(selectedCoordinate == nil)

                    Divider()

                    simulationControls

                    Text(
                        "Click the map to place a marker. "
                        + "Select and drag it to adjust the location."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Leave room for the fields' borders and focus rings.
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
            }
            // Prevent scrolling content from overlapping the device section.
            .scrollClipDisabled(false)
            .padding(.horizontal, -6)

            Divider()
                .padding(.top, 16)
                .padding(.bottom, 16)

            deviceControls
        }
        .padding(20)
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .textFieldStyle(.roundedBorder)
        .glassEffect(
            .regular,
            in: RoundedRectangle(cornerRadius: 26)
        )
    }

    private var sidebarHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Location Changer")
                    .font(.headline)

                Text(sessionStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                chooseBackend()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Choose backend")
            .disabled(backendControlsDisabled)
        }
    }

    // MARK: - Search controls

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Search")
                .font(.subheadline.weight(.semibold))

            TextField("Place or address", text: $searchQuery)
                .onSubmit {
                    beginSearch()
                }

            Button {
                beginSearch()
            } label: {
                HStack(spacing: 8) {
                    if isSearching {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }

                    Text(isSearching ? "Searching…" : "Search")
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(
                isSearching ||
                searchQuery.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            )
        }
    }

    private func beginSearch() {
        guard !isSearching,
              !searchQuery.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty else {
            return
        }

        isSearching = true

        Task {
            await searchLocation()
        }
    }

    // MARK: - Native map

    private var locationMap: some View {
        LocationMapView(
            latitude: $latitude,
            longitude: $longitude,
            focusRequest: mapFocusRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    // MARK: - Coordinate fields

    private var coordinateFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Selected coordinates")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Latitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−90 to 90", text: $latitude)
                    .monospacedDigit()
                    .onSubmit {
                        centerOnSelection()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Longitude")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("−180 to 180", text: $longitude)
                    .monospacedDigit()
                    .onSubmit {
                        centerOnSelection()
                    }
            }
        }
    }

    private func updateCoordinates(
        _ coordinate: CLLocationCoordinate2D
    ) {
        // Keep decimal-point formatting independent of regional settings.
        let locale = Locale(identifier: "en_US_POSIX")

        latitude = String(
            format: "%.7f",
            locale: locale,
            coordinate.latitude
        )

        longitude = String(
            format: "%.7f",
            locale: locale,
            coordinate.longitude
        )
    }

    private func centerOnSelection() {
        guard selectedCoordinate != nil else {
            status = "Enter valid coordinates using a decimal point"
            return
        }

        mapFocusRequest = UUID()
    }

    // MARK: - Simulation controls

    private var simulationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Simulation")
                .font(.subheadline.weight(.semibold))

            Button {
                guard deviceConnection.state.canStart,
                      !isStarting,
                      !isCheckingDevices else {
                    return
                }

                guard let coordinate = selectedCoordinate else {
                    status = "Enter valid coordinates"
                    return
                }

                Task {
                    await startSimulation(at: coordinate)
                }
            } label: {
                Label(
                    isStarting ? "Starting…" : "Start simulation",
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(
                !deviceConnection.state.canStart ||
                isStarting ||
                isCheckingDevices ||
                selectedCoordinate == nil
            )

            Button {
                // The backend sets .stopping and guards against duplicates.
                Task {
                    await stopSimulation()
                }
            } label: {
                Label(
                    isStopping ? "Stopping…" : "Stop / restore location",
                    systemImage: "stop.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!deviceConnection.state.canStop)

            if hasSimulationSession {
                Text("Changing the selection won't update this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Device and connection status

    private var deviceControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let checkedAt = lastDeviceCheck {
                if discoveredDevices.isEmpty {
                    Label(
                        "No device found",
                        systemImage: "iphone.slash"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(discoveredDevices.indices, id: \.self) { index in
                        let device = discoveredDevices[index]

                        HStack(spacing: 10) {
                            Image(systemName: device.connectionSymbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(device.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .help(device.name)

                                Text("iOS \(device.version)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            Text(device.connectionLabel)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(
                                    Color.accentColor.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                    }
                }

                HStack(spacing: 4) {
                    Text("Last checked")
                    Text(checkedAt, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            } else {
                Label(
                    "Connection not checked",
                    systemImage: "iphone"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button {
                guard !isCheckingDevices,
                      !isStarting,
                      !deviceConnection.state.isBusy else {
                    return
                }

                isCheckingDevices = true

                Task {
                    await listDevices()
                }
            } label: {
                Label(
                    isCheckingDevices ? "Checking…" : "Refresh connection",
                    systemImage: "arrow.clockwise"
                )
                .frame(maxWidth: .infinity)
            }
            .disabled(
                isCheckingDevices ||
                isStarting ||
                deviceConnection.state.isBusy
            )

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Backend selection

    private func chooseBackend() {
        guard !backendControlsDisabled else {
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Choose pymobiledevice3"
        panel.message = """
        Select the executable inside your project's .venv/bin folder.
        """
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK,
              let url = panel.url else {
            return
        }

        do {
            try deviceConnection.selectExecutable(url)
            status = "Backend selected: \(url.lastPathComponent)"
        } catch {
            status = error.localizedDescription
        }
    }

    // MARK: - Address search

    private func searchLocation() async {
        defer { isSearching = false }

        let searchService = LocationSearchService()

        do {
            guard let result = try await searchService.search(
                query: searchQuery
            ) else {
                status = "No places found"
                return
            }

            updateCoordinates(result.location.coordinate)
            mapFocusRequest = UUID()
            status = "Selected: \(result.name ?? searchQuery)"
        } catch {
            status = "Search failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Device discovery

    private func listDevices() async {
        defer { isCheckingDevices = false }
        status = "Looking for an iPhone…"

        do {
            let devices = try await deviceConnection.listDevices()

            discoveredDevices = devices
            lastDeviceCheck = Date()

            status = devices.isEmpty
                ? "No devices found. Check USB or Wi-Fi connectivity."
                : "Device discovery completed"
        } catch {
            // Don't show an old snapshot as a fresh result.
            discoveredDevices = []
            lastDeviceCheck = nil
            status = "Device check failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Session actions

    private func startSimulation(
        at coordinate: CLLocationCoordinate2D
    ) async {
        guard deviceConnection.state.canStart else {
            return
        }

        status = "Checking device and starting simulation…"

        do {
            // The backend now owns discovery, validation, and session state.
            let devices = try await deviceConnection.startSimulation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )

            discoveredDevices = devices
            lastDeviceCheck = Date()
            status = "Simulation launched — verify in Maps"
        } catch {
            // Clear the old snapshot when starting couldn't be completed.
            discoveredDevices = []
            lastDeviceCheck = nil
            status = "Couldn't start: \(error.localizedDescription)"
        }
    }
    private func stopSimulation() async {
        guard deviceConnection.state.canStop else {
            return
        }

        status = "Stopping simulation…"

        do {
            try await deviceConnection.stopSimulation()

            // No local flags to reset: the backend transitions to .idle.
            status = "Clear completed — verify real location in Maps"
        } catch {
            // The backend preserves .cleanupRequired when cleanup fails.
            status = "Couldn't restore: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView(deviceConnection: AppDelegate().deviceConnection)
}
