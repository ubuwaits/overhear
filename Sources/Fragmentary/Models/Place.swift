import FragmentaryDSP

enum Place: CaseIterable, Identifiable, Sendable {
    case afterClosing
    case cinemaAfterCredits
    case openShutters
    case thinWall
    case hotelCorridor
    case carParkAtDawn
    case kitchenRadio1979

    var id: Self { self }

    var title: String {
        switch self {
        case .afterClosing: "In an empty mall"
        case .cinemaAfterCredits: "At the movies"
        case .openShutters: "Through an open window"
        case .thinWall: "Through a thin wall"
        case .hotelCorridor: "In a hotel corridor"
        case .carParkAtDawn: "In a parking garage"
        case .kitchenRadio1979: "Through a kitchen radio"
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
