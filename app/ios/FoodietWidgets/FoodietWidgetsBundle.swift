//
//  FoodietWidgetsBundle.swift
//  FoodietWidgets
//
//  foodiet 홈스크린 위젯 번들 — 기획안 §4.1 / §4.4 / §4.5.
//

import WidgetKit
import SwiftUI

@main
struct FoodietWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickLogWidget()
        RemainingWidget()
        CoachTipWidget()
    }
}
