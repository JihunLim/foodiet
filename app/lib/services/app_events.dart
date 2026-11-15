/// 콘텐츠 열람·행동 측정 — `app_events` 테이블에 fire-and-forget INSERT.
///
/// 새 콘텐츠(피드백·레슨·체크인·뭐 먹지·투약)가 실제로 쓰이는지 보기 위한 최소 계측.
/// 실패(오프라인, 0017 미적용 DB 등)는 조용히 무시한다 — 측정이 기능을 막으면 안 된다.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppEvents {
  AppEvents._();

  static Future<void> log(String name,
      [Map<String, Object?> props = const {}]) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client.from('app_events').insert({
        'user_id': uid,
        'name': name,
        'props': props,
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[app-events] $name failed: $e');
    }
  }
}
