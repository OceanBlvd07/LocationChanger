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
            Map()
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
