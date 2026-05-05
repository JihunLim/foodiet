#!/usr/bin/env python3
"""
foodiet 앱 아이콘 — 1024x1024 마스터 PNG 생성.

브랜드 감성:
  - 배경: coral500 (#FF8A5B)  (theme/foodiet_tokens.dart FoodietColors.coral500)
  - 딸기 몸체: cream00 (#FFFDFA)
  - 잎: leaf500 (#7FB77E) / 줄기 leaf700 (#5C9A5B)
  - 씨앗: mealBreakfast (#F7D36A)

flutter_launcher_icons 가 이 PNG 로부터 전체 iOS 사이즈를 생성하므로
iOS 요구대로 불투명(opaque) 이 되도록 배경을 완전히 채운다.
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024

# Brand colors (sync with lib/theme/foodiet_tokens.dart).
CORAL500 = (255, 138, 91, 255)   # #FF8A5B
CORAL600 = (238, 112, 66, 255)   # #EE7042 — shadow hint
CREAM00 = (255, 253, 250, 255)   # #FFFDFA
LEAF500 = (127, 183, 126, 255)   # #7FB77E
LEAF700 = (92, 154, 91, 255)     # #5C9A5B
SEED = (247, 211, 106, 255)      # #F7D36A (mealBreakfast)


def strawberry_body_outline() -> list[tuple[float, float]]:
    """딸기 실루엣. 상단은 부드러운 원호, 하단은 뾰족하지만 둥그스름."""
    cx, cy_top = SIZE // 2, 330      # 상단 시작 y
    cy_shoulder = 560                 # 허리 부분 (원→삼각형 전환)
    cy_bot = 900                      # 바닥 뾰족 끝
    half_w = 260                      # 최대 반 폭

    points: list[tuple[float, float]] = []

    # 상단 반원 — 왼쪽 어깨에서 오른쪽 어깨까지 베지어 근사.
    # 180° ~ 0° (시계 방향으로 상단 아치)
    arc_steps = 40
    for i in range(arc_steps + 1):
        t = i / arc_steps
        angle = math.pi - math.pi * t  # π → 0
        x = cx + half_w * math.cos(angle)
        # 상단은 살짝 납작하게 (shoulder 가 좀 아래까지 내려가게).
        y = cy_shoulder - (cy_shoulder - cy_top) * math.sin(angle)
        points.append((x, y))

    # 오른쪽 어깨에서 바닥까지 — 부드러운 커브.
    # 큐빅 베지어 근사: P0(shoulder_r), P1, P2, P3(bottom).
    p0 = (cx + half_w, cy_shoulder)
    p1 = (cx + half_w, cy_shoulder + 220)
    p2 = (cx + 90, cy_bot - 10)
    p3 = (cx, cy_bot)
    for i in range(1, 40):
        t = i / 40
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))

    # 바닥 → 왼쪽 어깨.
    p0 = (cx, cy_bot)
    p1 = (cx - 90, cy_bot - 10)
    p2 = (cx - half_w, cy_shoulder + 220)
    p3 = (cx - half_w, cy_shoulder)
    for i in range(1, 41):
        t = i / 40
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))

    return points


def leaves_outline(cx: float, cy: float, r_out: float, r_in: float, n: int = 10) -> list[tuple[float, float]]:
    """별 모양 잎 (꽃받침)."""
    pts: list[tuple[float, float]] = []
    for i in range(n):
        theta = math.pi * 2 * i / n - math.pi / 2
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(theta), cy + r * math.sin(theta)))
    return pts


def seed(draw_on: Image.Image, x: int, y: int, angle_deg: float) -> None:
    """작은 씨앗을 해당 각도로 회전해서 합성."""
    seed_img = Image.new("RGBA", (40, 60), (0, 0, 0, 0))
    sd = ImageDraw.Draw(seed_img)
    sd.ellipse([4, 4, 36, 56], fill=SEED)
    rotated = seed_img.rotate(angle_deg, resample=Image.BICUBIC, expand=True)
    rw, rh = rotated.size
    draw_on.paste(rotated, (x - rw // 2, y - rh // 2), rotated)


def main() -> None:
    img = Image.new("RGBA", (SIZE, SIZE), CORAL500)
    d = ImageDraw.Draw(img)

    # 1) 딸기 그림자 (살짝 어두운 톤으로 오프셋).
    body = strawberry_body_outline()
    shadow = [(x + 8, y + 10) for (x, y) in body]
    d.polygon(shadow, fill=CORAL600)

    # 2) 딸기 몸체 (크림색).
    d.polygon(body, fill=CREAM00)

    # 3) 잎 — 상단. 꽃받침 별 모양.
    leaf_cx, leaf_cy = SIZE // 2, 300
    d.polygon(
        leaves_outline(leaf_cx, leaf_cy + 10, r_out=180, r_in=72, n=12),
        fill=LEAF700,
    )
    d.polygon(
        leaves_outline(leaf_cx, leaf_cy, r_out=170, r_in=70, n=12),
        fill=LEAF500,
    )

    # 잎 중앙 작은 원 (꼭지).
    d.ellipse([leaf_cx - 34, leaf_cy - 34, leaf_cx + 34, leaf_cy + 34], fill=LEAF700)

    # 4) 씨앗 — 방사형으로 자연스럽게. body 중심 기준.
    body_cx, body_cy = SIZE // 2, 600
    seed_specs = [
        (-150, -90, -20),
        (-30, -120, 0),
        (110, -100, 15),
        (-190, 10, -25),
        (-80, -10, -5),
        (50, -20, 10),
        (170, 0, 20),
        (-160, 100, -15),
        (-50, 80, 0),
        (80, 90, 10),
        (180, 110, 25),
        (-110, 190, -10),
        (20, 170, 5),
        (130, 200, 15),
        (-40, 260, 0),
    ]
    for dx, dy, angle in seed_specs:
        seed(img, body_cx + dx, body_cy + dy, angle)

    # 5) 하이라이트 — 몸체 좌상단에 살짝 흰 하이라이트.
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    hd.ellipse([370, 420, 500, 540], fill=(255, 255, 255, 95))
    img = Image.alpha_composite(img, highlight)

    out_path = Path(__file__).resolve().parent.parent / "assets" / "icon" / "foodiet-icon.png"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # iOS 는 alpha 채널이 있는 아이콘을 거부하므로 RGB 로 플래튼.
    flat = Image.new("RGB", img.size, CORAL500[:3])
    flat.paste(img, mask=img.split()[-1])
    flat.save(out_path, "PNG", optimize=True)
    print(f"wrote {out_path} ({SIZE}x{SIZE})")


if __name__ == "__main__":
    main()
