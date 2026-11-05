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

## 기능 소개형 (앱 하나, 기능 여러 장)

앱 하나의 기능을 한 장에 하나씩. 2026-11-05 장표스냅 "강의 장표, 아직도 사진첩에 찍어 둬요?" 가 이 형식이다.
요즘 인스타 카드뉴스처럼 여백 넉넉하게, 아주 굵은 큰 제목, 앱 색 하나만 쓰고, 폰 화면은 카드 아래로 잘려 나가게.

- 표지: 앱 색 바탕 + 질문형 큰 제목 + 폰 세 대 부채꼴(`coverScreens`)
- 기능 장: 크림 바탕, 번호 동그라미 · 짧은 이름(`label`) · 큰 제목 · 한두 줄 설명 · 폰 화면(`screen`, `top` 으로 몇 분의 몇부터 보일지)
  또는 전후 비교(`before` · `after`, 비스듬한 사진 위에 초록 모서리로 잡힌 반듯한 장표)
- 마지막 장: 아이콘 · 한마디 · 체크 세 줄(`points`) · App Store 검색 안내

```
swiftc -parse-as-library -O feature.swift -o /tmp/cardnews-feature
/tmp/cardnews-feature <deck.json> <출력 폴더>
```

- `deck.json` 형식은 `feature-example.json`. 결과는 JPG(1080×1350).
- 중요한 곳이 화면 아래쪽 멀리 있으면 빈 가운데를 잘라 붙인 화면을 따로 만들어 쓴다(장표스냅 메모 장이 그랬다).
- 인스타는 자르기에서 4:5 로. 스레드는 일곱 장 그대로 올리면 된다.
