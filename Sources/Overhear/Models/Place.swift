import OverhearDSP

enum Place: CaseIterable, Identifiable, Sendable {
    case emptyMall
    case movieTheater
    case openWindow
    case thinWall
    case hotelCorridor
    case parkingGarage
    case kitchenRadio

    var id: Self { self }

    var title: String {
        switch self {
        case .emptyMall: "Empty mall"
        case .movieTheater: "Movie theater"
        case .openWindow: "Open window"
        case .thinWall: "Thin wall"
        case .hotelCorridor: "Hotel corridor"
        case .parkingGarage: "Parking garage"
        case .kitchenRadio: "Kitchen radio"
        }
    }

    var symbol: String {
        switch self {
        case .emptyMall: "building.2"
        case .openWindow: "window.vertical.open"
        case .thinWall: "rectangle.split.3x1"
        case .hotelCorridor: "door.left.hand.closed"
        case .movieTheater: "film"
        case .parkingGarage: "parkingsign"
        case .kitchenRadio: "radio"
        }
    }

    var dspValue: OverhearPlace {
        switch self {
        case .emptyMall: OverhearPlaceEmptyMall
        case .openWindow: OverhearPlaceOpenWindow
        case .thinWall: OverhearPlaceThinWall
        case .hotelCorridor: OverhearPlaceHotelCorridor
        case .movieTheater: OverhearPlaceMovieTheater
        case .parkingGarage: OverhearPlaceParkingGarage
        case .kitchenRadio: OverhearPlaceKitchenRadio
        }
    }
}
