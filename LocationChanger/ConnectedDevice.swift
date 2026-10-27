import Foundation

// Describes the device fields we want to read from the JSON output.
struct ConnectedDevice: Decodable {
    let name: String
    let version: String
    let identifier: String

    // Maps Python's JSON field names to our Swift property names.
    enum CodingKeys: String, CodingKey {
        case name = "DeviceName"
        case version = "ProductVersion"
        case identifier = "UniqueDeviceID"
    }
    
}

