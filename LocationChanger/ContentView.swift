import SwiftUI
import MapKit

struct ContentView: View {
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var status = "Enter coordinates"
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Location Changer")
                .font(.title)
            // Gives us a proxy that converts screen positions into map coordinates.
            MapReader { proxy in
                Map {
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

            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 600)
    }
}

#Preview {
    ContentView()
}
