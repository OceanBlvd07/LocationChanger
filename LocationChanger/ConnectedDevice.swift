import Foundation

struct ConnectedDevice: Decodable {
    let name: String
    let version: String
    let identifier: String

    // The backend reports "USB" or "Network".
    // Optional so a missing field doesn't break JSON decoding.
    let connectionType: String?

    var connectionLabel: String {
        switch connectionType {
        case "USB":
            return "USB"
        case "Network":
            return "Wi-Fi"
        default:
            return connectionType ?? "Unknown"
        }
    }

    var connectionSymbol: String {
        switch connectionType {
        case "USB":
            return "cable.connector"
        case "Network":
            return "wifi"
        default:
            return "questionmark.circle"
        }
    }

    enum CodingKeys: String, CodingKey {
        case name = "DeviceName"
        case version = "ProductVersion"
        case identifier = "UniqueDeviceID"
        case connectionType = "ConnectionType"
    }
}
