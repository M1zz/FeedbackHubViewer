# 카드뉴스 그리기 (인스타)

앱 마케팅 칸의 카드뉴스 뷰를 떼어 와 1080×1350 PNG 로 그린다.

```
swiftc -parse-as-library -O render.swift -o /tmp/cardnews-render
/tmp/cardnews-render <slides.json> <unused> <아이콘 file:// URL> <앱 이름> <출력 폴더>
```

- `slides.json` 형식은 `example.json`. `screen` 은 그 앱 레포 `docs/screenshots/raw/...` 의 실제 화면.
- 마지막 장에 `App Store 에서 "<앱 이름>" 검색` 이 자동으로 붙는다.
- 인스타 업로드는 JPG 로 바꿔서 (`sips -s format jpeg`).

## 목록형 (앱 여러 개 묶음)

검은 바탕, 표지에 아이콘 한 줄 + 아래 큰 글씨, 앱마다 실제 화면 한 장, 마지막 장에 검색 안내.
2026-11-04 "아이폰에 깔아 두면 은근 매일 여는 앱 5" 가 이 형식이다.

```
swiftc -parse-as-library -O listicle.swift -o /tmp/cardnews-listicle
/tmp/cardnews-listicle <deck.json> <출력 폴더>
```

- `deck.json` 형식은 `listicle-example.json`. `icon` 은 그 앱 `AppIcon.appiconset` 의 1024 PNG, `screen` 은 `docs/screenshots/raw/ko/...`.
- 화면은 위쪽 700px 만 보인다(`anchor: "bottom"` 이면 아래쪽). 중요한 것이 위에 있는 화면을 고른다.
- 결과는 바로 JPG(1080×1350). 인스타는 자르기에서 4:5 로 바꿔야 안 잘린다.
