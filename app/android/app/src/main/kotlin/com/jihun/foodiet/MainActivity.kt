package com.jihun.foodiet

import com.jihun.foodiet.ads.FoodietNativeAdFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // AdMob 네이티브 고급형 광고 팩토리 등록 — Dart 쪽 factoryId 와 동일해야 함.
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "foodietNativeCard",
            FoodietNativeAdFactory(context),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "foodietNativeCard")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
