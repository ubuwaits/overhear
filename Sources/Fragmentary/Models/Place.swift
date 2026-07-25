import FragmentaryDSP

enum Place: CaseIterable, Identifiable, Sendable {
    case afterClosing
    case openShutters
    case thinWall
    case hotelCorridor
    case cinemaAfterCredits
    case carParkAtDawn
    case kitchenRadio1979

    var id: Self { self }

    var title: String {
        switch self {
        case .afterClosing: "After Closing"
        case .openShutters: "Open Shutters"
        case .thinWall: "Thin Wall"
        case .hotelCorridor: "Hotel Corridor, Door 307"
        case .cinemaAfterCredits: "Cinema After the Last Credits"
        case .carParkAtDawn: "Car Park at Dawn"
        case .kitchenRadio1979: "Kitchen Radio"
        }
    }

    var symbol: String {
        switch self {
        case .afterClosing: "building.2"
        case .openShutters: "window.vertical.open"
        case .thinWall: "rectangle.split.3x1"
        case .hotelCorridor: "door.left.hand.closed"
        case .cinemaAfterCredits: "film"
        case .carParkAtDawn: "parkingsign"
        case .kitchenRadio1979: "radio"
        }
    }

    var dspValue: FragmentaryPlace {
        switch self {
        case .afterClosing: FragmentaryPlaceAfterClosing
        case .openShutters: FragmentaryPlaceOpenShutters
        case .thinWall: FragmentaryPlaceThinWall
        case .hotelCorridor: FragmentaryPlaceHotelCorridor
        case .cinemaAfterCredits: FragmentaryPlaceCinemaAfterCredits
        case .carParkAtDawn: FragmentaryPlaceCarParkAtDawn
        case .kitchenRadio1979: FragmentaryPlaceKitchenRadio1979
        }
    }
}
