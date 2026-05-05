# foodiet — legal / support static pages

GitHub Pages 로 올려서 App Store Connect 의 Privacy/Support URL 로 쓴다.

## 배포 방법 (GitHub Pages)

### 옵션 A — 기존 `foodiet` 리포지토리의 `docs/` 폴더 사용 (추천)

```bash
# 이 폴더의 모든 파일을 리포 루트의 docs/ 에 복사
cp -r appstore/legal/* /path/to/foodiet-repo/docs/
cd /path/to/foodiet-repo
git add docs/
git commit -m "chore(docs): add privacy + support pages for App Store"
git push
```

그런 다음 GitHub > Settings > Pages:
- **Source** = Deploy from a branch
- **Branch** = `main`
- **Folder** = `/docs`
- Save

2–3분 후 다음 URL 에서 접근 가능:
- https://JihunLim.github.io/foodiet/
- https://JihunLim.github.io/foodiet/privacy/
- https://JihunLim.github.io/foodiet/support/

### 옵션 B — 별도 `foodiet-site` 리포 만들기

1. GitHub 에서 새 repo `foodiet-site` 생성 (public)
2. `appstore/legal/` 의 모든 파일을 해당 repo 의 루트로 복사
3. 첫 커밋 + push
4. Settings > Pages > Source = `main` / root

URL: `https://JihunLim.github.io/foodiet-site/privacy/` — App Store Connect 리스팅의 URL 도 이걸로 업데이트.

### 옵션 C — 이미 `JihunLim.github.io` (user site) 가 있으면

`JihunLim.github.io` repo 의 `foodiet/` 하위 경로에 복사 → `https://JihunLim.github.io/foodiet/privacy/`.

## App Store Connect 입력

| 필드 | URL |
|---|---|
| Support URL | `https://JihunLim.github.io/foodiet/support/` |
| Privacy Policy URL | `https://JihunLim.github.io/foodiet/privacy/` |
| Marketing URL (옵션) | `https://JihunLim.github.io/foodiet/` |

> URL 은 HTTPS 여야 하고, 24×7 접근 가능해야 Apple 리뷰를 통과해.
