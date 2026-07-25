import Foundation
import FragmentaryDSP

enum Place: String, CaseIterable, Identifiable, Sendable {
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
        case .kitchenRadio1979: "Kitchen Radio, 1979"
        }
    }

    var subtitle: String {
        switch self {
        case .afterClosing: "An empty shopping arcade at night"
        case .openShutters: "Music crossing an Italian square"
        case .thinWall: "The room next door, just audible"
        case .hotelCorridor: "Music leaking beneath a distant door"
        case .cinemaAfterCredits: "A dark auditorium absorbing the final song"
        case .carParkAtDawn: "Concrete decks returning every phrase"
        case .kitchenRadio1979: "A small speaker remembered from another room"
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
