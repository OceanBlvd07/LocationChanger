import SwiftUI
import MapKit

struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Enter coordinates"
    
    // Stores the address or place name entered in the search field.
    @State private var searchQuery = ""

    // Controls which area the map displays.
    @State private var cameraPosition: MapCameraPosition = .automatic

    // Prevents multiple searches from running at once.
    @State private var isSearching = false
    
    // Points to the Python tool installed in this project's environment.
    private let deviceConnection = DeviceConnection(
        executableURL: URL(
            fileURLWithPath:
                "/Users/markoandruhiv/Documents/LocationChanger/.venv/bin/pymobiledevice3"
        )
    )
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Location Changer")
                .font(.title)
            HStack {
                TextField("Search for a place or address", text: $searchQuery)

                Button(isSearching ? "Searching…" : "Search") {
                    Task {
                        await searchLocation()
                    }
                }
                .disabled(
                    isSearching ||
                    searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            // Gives us a proxy that converts screen positions into map coordinates.
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    // Show a pin only when both fields contain valid coordinates.
                    if let lat = Double(latitude),
                       let lon = Double(longitude),
                       (-90...90).contains(lat),
                       (-180...180).contains(lon) {
                        Marker(
                            "Selected location",
                            coordinate: CLLocationCoordinate2D(
                                latitude: lat,
                                longitude: lon
                            )
                        )
                    }
                }
                .onTapGesture { position in
                    // Convert the click's position within the map to GPS coordinates.
                    if let coordinate = proxy.convert(position, from: .local) {
                        // Updating @State refreshes the fields and moves the pin.
                        latitude = String(format: "%.6f", coordinate.latitude)
                        longitude = String(format: "%.6f", coordinate.longitude)
                    }
                }
            }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            TextField("Latitude", text: $latitude)
            TextField("Longitude", text: $longitude)
            Button("Check coordinates") {
                guard let lat = Double(latitude),
                      let lon = Double(longitude),
                      lat.isFinite,
                      lon.isFinite,
                      (-90...90).contains(lat),
                      (-180...180).contains(lon) else {
                    status = "Enter valid coordinates"
                    return
                }

                status = "Selected: \(lat), \(lon)"
            }
            Button("List connected devices") {
                do {
                    // Launch the command; its output appears in Xcode's console.
                    _ = try deviceConnection.listDevices()
                    status = "Device check launched — see Xcode console"
                } catch {
                    // Include the error domain, code, and underlying details.
                    let details = error as NSError
                    print("Device launch error:", details.domain, details.code)
                    print("Details:", details.userInfo)

                    status = "Couldn't launch device check: \(error.localizedDescription)"
                }
            }

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 600)
    }
    @MainActor
    private func searchLocation() async {
        isSearching = true

        // Restore the button whether the search succeeds or fails.
        defer { isSearching = false }

        let searchService = LocationSearchService()

        do {
            guard let result = try await searchService.search(query: searchQuery) else {
                status = "No places found"
                return
            }

            // Update the fields and pin using the returned location.
            let coordinate = result.location.coordinate
            latitude = String(format: "%.6f", coordinate.latitude)
            longitude = String(format: "%.6f", coordinate.longitude)

            // Move the map to the selected place.
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.02,
                        longitudeDelta: 0.02
                    )
                )
            )

            status = "Selected: \(result.name ?? searchQuery)"
        } catch {
            // Display errors passed back by the service.
            status = "Search failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
}
