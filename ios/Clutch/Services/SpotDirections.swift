import MapKit
import UIKit

/// Walking directions to a spot in her own maps app, Apple Maps or Google
/// Maps (the app when it's installed, the website when it isn't).
@MainActor
enum SpotDirections {
    static func openInAppleMaps(_ location: ProductLocation) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: location.coordinate))
        item.name = location.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    static func openInGoogleMaps(_ location: ProductLocation) {
        let destination = "\(location.latitude),\(location.longitude)"
        if let app = URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=walking"),
           UIApplication.shared.canOpenURL(app) {
            UIApplication.shared.open(app)
        } else if let web = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(destination)&travelmode=walking") {
            UIApplication.shared.open(web)
        }
    }
}
