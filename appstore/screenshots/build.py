#!/usr/bin/env python3
"""App Store 스크린샷 컴포지터.

원본 (`raw/01.PNG` ~ `08.PNG`) 1320×2868 을 그대로 살리면서, 위쪽 카피 영역과
아래쪽 화면 영역으로 나눠 합성한다.

산출물:
  - `iphone_6_9/01.png` ~ `08.png` (1320×2868, App Store iPhone 6.9")
  - `ipad_13/01.png` ~ `08.png` (2064×2752, App Store iPad 13")

iPad 는 foodiet 가 540 max-width 레터박스로 표시하기 때문에 iPhone raw 를
그대로 가운데 두고 좌우 크림 패딩만 추가 — 실제 iPad 사용 화면을 충실히 재현.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "raw"

# ── 브랜드 컬러 (foodiet_tokens.dart 미러) ────────────────────────
CREAM00  = (0xFF, 0xFD, 0xFA)
CREAM50  = (0xFB, 0xF6, 0xEF)
CORAL50  = (0xFF, 0xF2, 0xEA)
CORAL100 = (0xFF, 0xE4, 0xD1)
CORAL500 = (0xFF, 0x8A, 0x5B)
CORAL700 = (0xCC, 0x5A, 0x31)
WARM500  = (0x6B, 0x64, 0x54)
WARM700  = (0x3E, 0x3A, 0x31)
WARM900  = (0x22, 0x1F, 0x1A)

# ── 폰트 ──────────────────────────────────────────────────────────
# macOS 의 AppleSDGothicNeo.ttc 를 사용. ttc 는 PIL 의 index 인자로 weight 선택.
SD_GOTHIC = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

def font(weight: str, size: int) -> ImageFont.FreeTypeFont:
    """weight: 'bold' | 'medium' | 'regular'."""
    idx = {"bold": 8, "medium": 4, "regular": 0}.get(weight, 0)
    return ImageFont.truetype(SD_GOTHIC, size, index=idx)

# ── 카피 ──────────────────────────────────────────────────────────
# (강조 헤드라인, 부제, 헤더 배경 컬러)
SLIDES: list[tuple[str, str, str, tuple[int, int, int]]] = [
    ("01.PNG", "사진 한 장이면 끝.",
     "찍으면 칼로리·탄단지가 자동으로 계산돼.",
     CORAL50),

    ("02.PNG", "내가 먹은 모든 끼니,\n한눈에.",
     "날짜·끼니별로 정리되는 식사 일기.",
     CREAM50),

    ("03.PNG", "AI 가 뜯어본 한 끼.",
     "품목별 칼로리, 신뢰도까지 보여줘.",
     CORAL50),

    ("04.PNG", "이대로 가면\n목표에 도달할까?",
     "체중 추이 + 예측이 답을 알려줘.",
     CORAL100),

    ("05.PNG", "이번 주, 잘 먹고 있어?",
     "달성률·기록일·코치 한마디까지.",
     CREAM50),

    ("06.PNG", "내 식습관의 진짜 모습.",
     "끼니 비중·평균 단백질·자주 먹은 음식.",
     CORAL50),

    ("07.jpg", "하루 식단을\n한 장으로 공유.",
     "친구·트레이너·코치에게 바로.",
     CORAL100),

    ("08.PNG", "끼니 시간에 맞춰\n부드럽게 알려줘.",
     "아침·점심·저녁 따로 시간 설정.",
     CORAL50),
]

# ── 레이아웃 상수 ─────────────────────────────────────────────────
# 두 디바이스 공통 패턴:
#   - 상단에 헤더 영역 (브랜드색 + 헤드라인 + 서브카피)
#   - 그 아래에 폰 화면을 라운디드 + 그림자 처리해서 배치
SHOT_RADIUS = 64
SHADOW_BLUR = 28

def round_corners(im: Image.Image, radius: int) -> Image.Image:
    """이미지 모서리를 라운딩."""
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, im.size[0], im.size[1]), radius=radius, fill=255
    )
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im.convert("RGBA"), (0, 0), mask)
    return out

def draw_text_centered_multiline(
    draw: ImageDraw.ImageDraw,
    text: str,
    cx: int,
    top_y: int,
    fnt: ImageFont.FreeTypeFont,
    fill: tuple[int, int, int],
    line_spacing: int = 20,
) -> int:
    """여러 줄 텍스트를 가로 중앙 정렬로 그리고 다음 y 반환."""
    y = top_y
    for line in text.split("\n"):
        bbox = draw.textbbox((0, 0), line, font=fnt)
        w = bbox[2] - bbox[0]
        h = bbox[3] - bbox[1]
        draw.text((cx - w // 2, y - bbox[1]), line, font=fnt, fill=fill)
        y += h + line_spacing
    return y - line_spacing

def compose(
    raw_name: str,
    headline: str,
    subtitle: str,
    header_color: tuple[int, int, int],
    *,
    canvas_w: int,
    canvas_h: int,
    header_h: int,
    shot_w: int,
    brand_size: int,
    head_size: int,
    sub_size: int,
    head_top: int,
) -> Image.Image:
    canvas = Image.new("RGB", (canvas_w, canvas_h), CREAM00)
    draw = ImageDraw.Draw(canvas)

    # 헤더 배경 — 연한 코랄/크림 풀블리드.
    draw.rectangle((0, 0, canvas_w, header_h), fill=header_color)

    # 작은 푸디 마크 (🍓 + foodiet 로고타입).
    brand_fnt = font("bold", brand_size)
    brand = "🍓 foodiet"
    bbox = draw.textbbox((0, 0), brand, font=brand_fnt)
    bw = bbox[2] - bbox[0]
    draw.text(
        (canvas_w // 2 - bw // 2, head_top - brand_size - 60),
        brand, font=brand_fnt, fill=CORAL700,
    )

    # 헤드라인.
    h_fnt = font("bold", head_size)
    end_y = draw_text_centered_multiline(
        draw, headline, canvas_w // 2, head_top, h_fnt, WARM900,
        line_spacing=int(head_size * 0.25),
    )

    # 서브 카피.
    s_fnt = font("medium", sub_size)
    draw_text_centered_multiline(
        draw, subtitle, canvas_w // 2, end_y + int(sub_size * 0.9),
        s_fnt, WARM500, line_spacing=10,
    )

    # 폰 스크린샷 합성 (라운딩 + 그림자).
    shot_path = RAW / raw_name
    shot = Image.open(shot_path).convert("RGB")
    sw, sh = shot.size
    new_h = int(sh * (shot_w / sw))
    shot = shot.resize((shot_w, new_h), Image.LANCZOS)
    shot = round_corners(shot, SHOT_RADIUS)

    # 그림자 — RGBA 검정 ellipse 를 blur.
    shadow = Image.new(
        "RGBA",
        (shot_w + SHADOW_BLUR * 4, new_h + SHADOW_BLUR * 4),
        (0, 0, 0, 0),
    )
    sdraw = ImageDraw.Draw(shadow)
    sdraw.rounded_rectangle(
        (SHADOW_BLUR * 2, SHADOW_BLUR * 2,
         shot_w + SHADOW_BLUR * 2, new_h + SHADOW_BLUR * 2),
        radius=SHOT_RADIUS,
        fill=(0, 0, 0, 60),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))

    sx = (canvas_w - shot_w) // 2
    sy = header_h - 40                 # 헤더와 살짝 겹치게
    canvas.paste(shadow, (sx - SHADOW_BLUR * 2, sy - SHADOW_BLUR * 2 + 24),
                 shadow)
    canvas.paste(shot, (sx, sy), shot)

    return canvas


# ── 디바이스별 프리셋 ─────────────────────────────────────────────
PRESETS: dict[str, dict] = {
    "iphone_6_9": dict(
        canvas_w=1320, canvas_h=2868,
        header_h=880,
        shot_w=1056,                    # 80% 폭
        brand_size=56,
        head_size=110, head_top=240,
        sub_size=50,
    ),
    "iphone_6_5": dict(
        canvas_w=1242, canvas_h=2688,
        header_h=820,
        shot_w=994,                     # 80% 폭
        brand_size=52,
        head_size=104, head_top=224,
        sub_size=48,
    ),
    "ipad_13": dict(
        canvas_w=2064, canvas_h=2752,
        header_h=820,
        shot_w=920,                     # 좁고 길어 보이게 — iPad 에서도 폰처럼 letterbox 되는 실제 화면을 반영
        brand_size=66,
        head_size=130, head_top=260,
        sub_size=58,
    ),
}


def main():
    for device, preset in PRESETS.items():
        out_dir = ROOT / device
        out_dir.mkdir(parents=True, exist_ok=True)
        for raw_name, headline, subtitle, color in SLIDES:
            out_name = raw_name.lower().replace(".jpg", ".png")
            composed = compose(
                raw_name, headline, subtitle, color, **preset,
            )
            composed.save(out_dir / out_name, "PNG", optimize=True)
            print(f"  wrote {out_dir / out_name}  "
                  f"({composed.size[0]}×{composed.size[1]})")


if __name__ == "__main__":
    main()
