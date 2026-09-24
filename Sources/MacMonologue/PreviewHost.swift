import Foundation

/// Whether Xcode is rendering a preview of a view right now.
///
/// A preview must never open the camera, ask for permissions, download
/// anything or write the user's settings: the views are shown with data set by
/// hand, and everything that touches the outside world checks this first.
enum PreviewHost {
    static let isActive = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}
