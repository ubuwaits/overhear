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
        case .afterClosing: "Empty mall"
        case .cinemaAfterCredits: "Movie theater"
        case .openShutters: "Open window"
        case .thinWall: "Thin wall"
        case .hotelCorridor: "Hotel corridor"
        case .carParkAtDawn: "Parking garage"
        case .kitchenRadio1979: "Kitchen radio"
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
