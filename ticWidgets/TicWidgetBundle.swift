import WidgetKit
import SwiftUI

@main
struct TicWidgetBundle: WidgetBundle {
    var body: some Widget {
        TicLiveActivity()
        SmallTicWidget()
        MediumTicWidget()
    }
}
