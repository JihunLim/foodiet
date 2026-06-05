package com.jihun.foodiet.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.jihun.foodiet.MainActivity
import com.jihun.foodiet.R
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * foodiet 홈스크린 위젯들 — 기획안 §4.1 / §4.4 / §4.5.
 *
 * 데이터 소스: `home_widget` 플러그인이 `HomeWidgetPreferences` SharedPreferences 에
 * 기록한 키. Flutter 쪽 `FoodietWidgetService.sync(...)` 가 채워 넣는다.
 *
 * 탭 동작: 전체 위젯 영역을 PendingIntent 로 감싸 `foodiet://widget/<target>` URI 로
 * MainActivity 를 실행 → Flutter 측 `home_widget.widgetClicked` 스트림으로 전달되고
 * `main.dart` 가 go_router 로 해당 화면으로 라우팅한다.
 */
private const val SCHEME = "foodiet"
private const val HOST = "widget"

private fun launchIntent(context: Context, target: String): PendingIntent {
    val uri = Uri.parse("$SCHEME://$HOST/$target")
    val intent = Intent(context, MainActivity::class.java).apply {
        // home_widget 의 widgetClicked/initiallyLaunchedFromHomeWidget 는
        // 이 LAUNCH 액션일 때만 동작한다 (ACTION_VIEW 면 URI 가 Flutter 로 전달 안 됨).
        action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        data = uri
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    return PendingIntent.getActivity(
        context,
        target.hashCode(),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/**
 * 빠른 기록 딥링크 — `foodiet://widget/log?fav=<id>`.
 * 앱을 열고 즐겨찾기를 사진/분석 없이 즉시 기록한다 (main.dart 가 처리).
 * favId 별로 requestCode 를 달리해 PendingIntent 충돌을 막는다.
 */
private fun quickLogIntent(context: Context, favId: String): PendingIntent {
    val uri = Uri.parse("$SCHEME://$HOST/log?fav=$favId")
    val intent = Intent(context, MainActivity::class.java).apply {
        // home_widget 의 widgetClicked/initiallyLaunchedFromHomeWidget 는
        // 이 LAUNCH 액션일 때만 동작한다 (ACTION_VIEW 면 URI 가 Flutter 로 전달 안 됨).
        action = HomeWidgetLaunchIntent.HOME_WIDGET_LAUNCH_ACTION
        data = uri
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
    }
    return PendingIntent.getActivity(
        context,
        ("log:$favId").hashCode(),
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

/** 빠른 기록 위젯 — 탭 → 카메라 화면 바로 + 즐겨찾기 1탭 재기록. */
class QuickLogWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val entryCount = prefs.getInt("entry_count", 0)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fd_widget_quick_log)
            views.setTextViewText(R.id.fd_ql_sub, "오늘 ${entryCount}장 기록됨")
            views.setOnClickPendingIntent(
                R.id.fd_quick_log_root,
                launchIntent(context, "camera"),
            )
            bindFavorite(context, views, prefs, R.id.fd_ql_fav1, "fav1_id", "fav1_name")
            bindFavorite(context, views, prefs, R.id.fd_ql_fav2, "fav2_id", "fav2_name")
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    /** 즐겨찾기 한 줄 바인딩 — 데이터가 있으면 VISIBLE + 재기록 PendingIntent. */
    private fun bindFavorite(
        context: Context,
        views: RemoteViews,
        prefs: android.content.SharedPreferences,
        viewId: Int,
        idKey: String,
        nameKey: String,
    ) {
        val favId = prefs.getString(idKey, "") ?: ""
        val favName = prefs.getString(nameKey, "") ?: ""
        if (favId.isEmpty() || favName.isEmpty()) {
            views.setViewVisibility(viewId, android.view.View.GONE)
            return
        }
        views.setViewVisibility(viewId, android.view.View.VISIBLE)
        views.setTextViewText(viewId, "↻ $favName")
        views.setOnClickPendingIntent(viewId, quickLogIntent(context, favId))
    }
}

/** 남은 칼로리 + 탄·단·지 위젯 — 탭 → 홈 탭. */
class RemainingWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val remaining = prefs.getInt("remaining_kcal", 0)
        val consumed = prefs.getInt("consumed_kcal", 0)
        val target = prefs.getInt("target_kcal", 0)
        val carb = prefs.getInt("carb_g", 0)
        val protein = prefs.getInt("protein_g", 0)
        val fat = prefs.getInt("fat_g", 0)

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fd_widget_remaining)
            views.setTextViewText(R.id.fd_r_kcal, remaining.toString())
            views.setTextViewText(R.id.fd_r_usage, "섭취 $consumed / $target kcal")
            views.setTextViewText(R.id.fd_r_carb, "${carb}g")
            views.setTextViewText(R.id.fd_r_protein, "${protein}g")
            views.setTextViewText(R.id.fd_r_fat, "${fat}g")
            views.setOnClickPendingIntent(
                R.id.fd_remaining_root,
                launchIntent(context, "home"),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** 푸디의 한마디 위젯 — 탭 → 홈 탭 (코치 카드 강조 지점). */
class CoachTipWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val emoji = prefs.getString("coach_emoji", "🍓") ?: "🍓"
        val headline = prefs.getString("coach_headline", "오늘도 한 장씩 기록해볼까?")
            ?: "오늘도 한 장씩 기록해볼까?"
        val tip = prefs.getString("coach_tip", "첫 사진 한 장으로 푸디의 조언을 받아봐.")
            ?: "첫 사진 한 장으로 푸디의 조언을 받아봐."

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.fd_widget_coach)
            views.setTextViewText(R.id.fd_c_emoji, emoji)
            views.setTextViewText(R.id.fd_c_headline, headline)
            views.setTextViewText(R.id.fd_c_tip, tip)
            views.setOnClickPendingIntent(
                R.id.fd_coach_root,
                launchIntent(context, "coach"),
            )
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}

/** Flutter 쪽에서 `HomeWidget.updateWidget` 호출 시 invoke 되는 helper. */
fun forceRefresh(context: Context, providerClass: Class<out AppWidgetProvider>) {
    val mgr = AppWidgetManager.getInstance(context)
    val ids = mgr.getAppWidgetIds(ComponentName(context, providerClass))
    if (ids.isNotEmpty()) {
        val intent = Intent(context, providerClass).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        context.sendBroadcast(intent)
    }
}
