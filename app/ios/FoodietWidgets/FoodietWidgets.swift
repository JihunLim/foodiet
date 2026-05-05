//
//  FoodietWidgets.swift
//  FoodietWidgets
//
//  기획안 §4.1 / §4.4 / §4.5 — WidgetKit 으로 세 종류 위젯을 제공한다.
//  데이터는 App Group `group.com.jihun.foodiet.widget` 의 UserDefaults 에서 읽는다.
//  Flutter 앱이 `FoodietWidgetService.sync(...)` 로 값을 써 넣으면 타임라인이 refresh 된다.
//
//  탭 동작은 `widgetURL(...)` 로 `foodiet://widget/<target>` 딥링크를 깔아,
//  Flutter 측 `home_widget.widgetClicked` 스트림과 `main.dart` 라우팅이 받아 처리한다.
//
//  @main 진입점은 `FoodietWidgetsBundle.swift` 에 있음.
//

import WidgetKit
import SwiftUI

private let appGroup = "group.com.jihun.foodiet.widget"

// MARK: - Colors (design-system/colors_and_type.css 미러)

private enum FD {
    static let cream00 = Color(red: 1.0, green: 0.992, blue: 0.980)
    static let cream50 = Color(red: 0.984, green: 0.965, blue: 0.937)
    static let cream100 = Color(red: 0.957, green: 0.929, blue: 0.886)
    static let coral500 = Color(red: 1.0, green: 0.541, blue: 0.357)
    static let coral100 = Color(red: 1.0, green: 0.894, blue: 0.820)
    static let leaf500 = Color(red: 0.498, green: 0.718, blue: 0.494)
    static let warm500 = Color(red: 0.420, green: 0.392, blue: 0.329)
    static let warm700 = Color(red: 0.243, green: 0.227, blue: 0.192)
    static let warm900 = Color(red: 0.133, green: 0.122, blue: 0.102)
    static let mealBreakfast = Color(red: 0.969, green: 0.827, blue: 0.416)
    static let mealDinner = Color(red: 0.545, green: 0.435, blue: 0.702)
}

// MARK: - Snapshot model

struct FoodietSnapshot {
    let nickname: String
    let remainingKcal: Int
    let consumedKcal: Int
    let targetKcal: Int
    let carbG: Int
    let proteinG: Int
    let fatG: Int
    let coachEmoji: String
    let coachHeadline: String
    let coachTip: String
    let entryCount: Int

    static let placeholder = FoodietSnapshot(
        nickname: "후니",
        remainingKcal: 1240,
        consumedKcal: 560,
        targetKcal: 1800,
        carbG: 78,
        proteinG: 32,
        fatG: 18,
        coachEmoji: "🍓",
        coachHeadline: "탄수 80g 남았어!",
        coachTip: "저녁은 단백질 위주로 가볼까?",
        entryCount: 2
    )

    static func load() -> FoodietSnapshot {
        let d = UserDefaults(suiteName: appGroup)
        func int(_ k: String) -> Int { (d?.object(forKey: k) as? Int) ?? 0 }
        func str(_ k: String, _ fallback: String) -> String {
            let v = d?.string(forKey: k) ?? ""
            return v.isEmpty ? fallback : v
        }
        return FoodietSnapshot(
            nickname: str("nickname", "너"),
            remainingKcal: int("remaining_kcal"),
            consumedKcal: int("consumed_kcal"),
            targetKcal: int("target_kcal"),
            carbG: int("carb_g"),
            proteinG: int("protein_g"),
            fatG: int("fat_g"),
            coachEmoji: str("coach_emoji", "🍓"),
            coachHeadline: str("coach_headline", "오늘도 한 장씩 기록해볼까?"),
            coachTip: str("coach_tip", "첫 사진 한 장으로 푸디의 조언을 받아봐."),
            entryCount: int("entry_count")
        )
    }
}

struct FoodietEntry: TimelineEntry {
    let date: Date
    let snapshot: FoodietSnapshot
}

struct FoodietProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoodietEntry {
        FoodietEntry(date: Date(), snapshot: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (FoodietEntry) -> Void) {
        completion(FoodietEntry(date: Date(), snapshot: FoodietSnapshot.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoodietEntry>) -> Void) {
        let entry = FoodietEntry(date: Date(), snapshot: FoodietSnapshot.load())
        // 앱이 saveWidgetData 후 updateWidget 호출하므로, 30분 뒤 안전망만 건다.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Helpers

private func deepLink(_ target: String) -> URL {
    URL(string: "foodiet://widget/\(target)")!
}

private extension View {
    /// iOS 17+ 에서는 containerBackground, 이하에서는 background.
    @ViewBuilder
    func fdWidgetBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(FD.cream50, for: .widget)
        } else {
            self.background(FD.cream50)
        }
    }
}

// MARK: - Quick Log Widget

struct QuickLogWidgetView: View {
    var entry: FoodietEntry
    var body: some View {
        let count = entry.snapshot.entryCount
        VStack(spacing: 6) {
            Text("🍓").font(.system(size: 30))
            Text("한 장 찍기")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(FD.warm900)
            Text(count > 0 ? "오늘 \(count)장 기록됨" : "오늘 기록 시작!")
                .font(.system(size: 11))
                .foregroundColor(FD.warm500)
            Text("📷 촬영")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(FD.coral500)
                .cornerRadius(12)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(deepLink("camera"))
    }
}

struct QuickLogWidget: Widget {
    let kind = "FoodietQuickLogWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodietProvider()) { entry in
            QuickLogWidgetView(entry: entry).fdWidgetBackground()
        }
        .configurationDisplayName("한 장 찍기")
        .description("카메라를 바로 열어 사진 한 장으로 기록해요.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Remaining Widget

struct RemainingWidgetView: View {
    var entry: FoodietEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("오늘의 남은 칼로리")
                        .font(.system(size: 11))
                        .foregroundColor(FD.warm500)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text("\(s.remainingKcal)")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundColor(FD.coral500)
                            .monospacedDigit()
                        Text("kcal 남음")
                            .font(.system(size: 11))
                            .foregroundColor(FD.warm500)
                    }
                    Text("섭취 \(s.consumedKcal) / \(s.targetKcal) kcal")
                        .font(.system(size: 11))
                        .foregroundColor(FD.warm700)
                        .monospacedDigit()
                }
                Spacer()
                ZStack {
                    Circle()
                        .stroke(FD.coral100, lineWidth: 6)
                        .frame(width: 52, height: 52)
                    Text("🍓").font(.system(size: 22))
                }
            }
            HStack(spacing: 6) {
                macroChip(label: "탄수", value: s.carbG,
                          bg: FD.mealBreakfast.opacity(0.18), fg: FD.mealBreakfast)
                macroChip(label: "단백", value: s.proteinG,
                          bg: FD.leaf500.opacity(0.18), fg: FD.leaf500)
                macroChip(label: "지방", value: s.fatG,
                          bg: FD.mealDinner.opacity(0.18), fg: FD.mealDinner)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink("home"))
    }

    private func macroChip(label: String, value: Int, bg: Color, fg: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(fg)
            Text("\(value)g")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(FD.warm900)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(10)
    }
}

struct RemainingWidget: Widget {
    let kind = "FoodietRemainingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodietProvider()) { entry in
            RemainingWidgetView(entry: entry).fdWidgetBackground()
        }
        .configurationDisplayName("남은 칼로리")
        .description("오늘의 남은 칼로리와 탄·단·지를 한눈에.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Coach Tip Widget

struct CoachTipWidgetView: View {
    var entry: FoodietEntry
    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(s.coachEmoji).font(.system(size: 22))
                Text("푸디의 한마디")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FD.coral500)
            }
            Text(s.coachHeadline)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(FD.warm900)
                .lineLimit(2)
            Text(s.coachTip)
                .font(.system(size: 12))
                .foregroundColor(FD.warm500)
                .lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLink("coach"))
    }
}

struct CoachTipWidget: Widget {
    let kind = "FoodietCoachTipWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoodietProvider()) { entry in
            CoachTipWidgetView(entry: entry).fdWidgetBackground()
        }
        .configurationDisplayName("푸디의 한마디")
        .description("오늘의 식단에 맞춘 푸디의 조언.")
        .supportedFamilies([.systemMedium])
    }
}
