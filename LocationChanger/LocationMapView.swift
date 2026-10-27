import SwiftUI
import MapKit
import AppKit

@MainActor
struct LocationMapView: NSViewRepresentable {
    @Binding var latitude: String
    @Binding var longitude: String

    // Changing this value requests that the map center on the selection.
    let focusRequest: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator

        map.isZoomEnabled = true
        map.isScrollEnabled = true

        // Keep the map flat so precise placement is easier.
        map.isPitchEnabled = false
        map.isRotateEnabled = false

        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.mapClicked(_:))
        )
        click.delegate = context.coordinator
        map.addGestureRecognizer(click)

        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator

        // Keep the coordinator connected to the latest SwiftUI bindings.
        coordinator.parent = self

        // MapKit controls the annotation while a native drag is in progress.
        guard !coordinator.isDragging else {
            return
        }

        guard let coordinate = validCoordinate else {
            if map.annotations.contains(where: {
                $0 === coordinator.annotation
            }) {
                map.removeAnnotation(coordinator.annotation)
            }

            return
        }

        if !map.annotations.contains(where: {
            $0 === coordinator.annotation
        }) {
            coordinator.annotation.coordinate = coordinate
            map.addAnnotation(coordinator.annotation)
        } else {
            let current = coordinator.annotation.coordinate

            if current.latitude != coordinate.latitude ||
                current.longitude != coordinate.longitude {
                coordinator.annotation.coordinate = coordinate
            }
        }

        // Editing coordinates moves the marker without constantly
        // resetting the user's zoom or map position.
        if coordinator.lastFocusRequest != focusRequest {
            coordinator.lastFocusRequest = focusRequest

            map.setRegion(
                MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(
                        latitudeDelta: 0.01,
                        longitudeDelta: 0.01
                    )
                ),
                animated: true
            )
        }
    }

    static func dismantleNSView(
        _ map: MKMapView,
        coordinator: Coordinator
    ) {
        coordinator.stopTrackingDrag()
        map.delegate = nil
    }

    private var validCoordinate: CLLocationCoordinate2D? {
        guard let lat = Double(latitude),
              let lon = Double(longitude),
              lat.isFinite,
              lon.isFinite,
              (-90...90).contains(lat),
              (-180...180).contains(lon) else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func updateCoordinates(_ coordinate: CLLocationCoordinate2D) {
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

    @MainActor
    final class Coordinator:
        NSObject,
        MKMapViewDelegate,
        NSGestureRecognizerDelegate
    {
        var parent: LocationMapView

        // Keep one annotation object rather than recreating it on every edit.
        let annotation = MKPointAnnotation()

        var isDragging = false
        var lastFocusRequest: UUID?

        private var dragTimer: Timer?
        private weak var draggingView: MKAnnotationView?
        private weak var draggingMap: MKMapView?

        init(parent: LocationMapView) {
            self.parent = parent
            super.init()

            annotation.title = "Selected location"
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard annotation === self.annotation else {
                return nil
            }

            let identifier = "selectedLocation"

            let marker = mapView.dequeueReusableAnnotationView(
                withIdentifier: identifier
            ) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )

            marker.annotation = annotation
            marker.markerTintColor = .systemRed
            marker.glyphImage = NSImage(
                systemSymbolName: "mappin",
                accessibilityDescription: nil
            )
            marker.isDraggable = true
            marker.canShowCallout = false
            marker.displayPriority = .required

            return marker
        }

        // Don't treat clicking a marker as clicking the map behind it.
        func gestureRecognizerShouldBegin(
            _ gestureRecognizer: NSGestureRecognizer
        ) -> Bool {
            guard let map = gestureRecognizer.view as? MKMapView else {
                return false
            }

            let point = gestureRecognizer.location(in: map)
            let annotationView = map.view(for: annotation)

            if let annotationView {
                let localPoint = annotationView.convert(point, from: map)

                if annotationView.bounds.contains(localPoint) {
                    return false
                }
            }

            return true
        }

        @objc func mapClicked(_ recognizer: NSClickGestureRecognizer) {
            guard !isDragging,
                  let map = recognizer.view as? MKMapView else {
                return
            }

            let point = recognizer.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)

            parent.updateCoordinates(coordinate)
        }

        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            switch newState {
            case .starting:
                isDragging = true
                startTrackingDrag(view: view, map: mapView)

            case .dragging:
                isDragging = true

            case .ending, .canceling:
                stopTrackingDrag()

                // MapKit supplies the final geographic position.
                if let coordinate = view.annotation?.coordinate {
                    parent.updateCoordinates(coordinate)
                }

                view.setDragState(.none, animated: false)
                isDragging = false

            case .none:
                if isDragging {
                    stopTrackingDrag()

                    if let coordinate = view.annotation?.coordinate {
                        parent.updateCoordinates(coordinate)
                    }

                    isDragging = false
                }

            @unknown default:
                break
            }
        }

        private func startTrackingDrag(
            view: MKAnnotationView,
            map: MKMapView
        ) {
            stopTrackingDrag()

            draggingView = view
            draggingMap = map

            // Sample the native marker during dragging to update the fields.
            let timer = Timer(timeInterval: 0.05, repeats: true) {
                [weak self] _ in

                Task { @MainActor [weak self] in
                    self?.updateDragCoordinates()
                }
            }

            dragTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func updateDragCoordinates() {
            guard isDragging,
                  let view = draggingView,
                  let map = draggingMap,
                  let container = view.superview else {
                return
            }

            // Remove the marker's visual offset to find its map anchor.
            let anchor = CGPoint(
                x: view.frame.midX - view.centerOffset.x,
                y: view.frame.midY - view.centerOffset.y
            )

            let coordinate = map.convert(
                anchor,
                toCoordinateFrom: container
            )

            parent.updateCoordinates(coordinate)
        }

        func stopTrackingDrag() {
            dragTimer?.invalidate()
            dragTimer = nil
            draggingView = nil
            draggingMap = nil
        }
    }
}
