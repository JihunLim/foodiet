package com.jihun.foodiet.ads

import android.content.Context
import android.view.LayoutInflater
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import com.jihun.foodiet.R
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

/**
 * AdMob 네이티브 고급형 광고 — 인사이트 탭 삽입용 Android 렌더러.
 *
 * policy 요구사항: "광고" 라벨 + headline + CTA. 컨텐츠와 명확히 구분.
 * 디자인은 foodiet 토큰 (cream-50 배경 + 코랄 CTA) 유지.
 */
class FoodietNativeAdFactory(private val context: Context) :
    GoogleMobileAdsPlugin.NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.fd_native_ad, null) as NativeAdView

        val headline = adView.findViewById<TextView>(R.id.fd_ad_headline)
        headline.text = nativeAd.headline
        adView.headlineView = headline

        val body = adView.findViewById<TextView>(R.id.fd_ad_body)
        if (nativeAd.body == null) {
            body.visibility = android.view.View.GONE
        } else {
            body.visibility = android.view.View.VISIBLE
            body.text = nativeAd.body
        }
        adView.bodyView = body

        val cta = adView.findViewById<Button>(R.id.fd_ad_cta)
        if (nativeAd.callToAction == null) {
            cta.visibility = android.view.View.INVISIBLE
        } else {
            cta.visibility = android.view.View.VISIBLE
            cta.text = nativeAd.callToAction
        }
        adView.callToActionView = cta

        // MediaView — AdMob policy 상 native advanced 는 MediaView 필수.
        // 아이콘/비디오/이미지는 MediaContent 가 자동 렌더한다.
        val media = adView.findViewById<MediaView>(R.id.fd_ad_media)
        adView.mediaView = media

        // 숨김 iconView placeholder — SDK 가 참조하지만 실제 렌더는 MediaView 담당.
        val icon = adView.findViewById<ImageView>(R.id.fd_ad_icon)
        adView.iconView = icon

        val advertiser = adView.findViewById<TextView>(R.id.fd_ad_advertiser)
        if (nativeAd.advertiser == null) {
            advertiser.visibility = android.view.View.GONE
        } else {
            advertiser.visibility = android.view.View.VISIBLE
            advertiser.text = nativeAd.advertiser
        }
        adView.advertiserView = advertiser

        // 필수 — 터치·노출 추적 시작.
        adView.setNativeAd(nativeAd)
        return adView
    }
}
