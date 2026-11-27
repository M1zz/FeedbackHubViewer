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

## 기능 소개형 — 빛번짐 (앱 하나, 짙은 바탕)

같은 7장 구성인데 바탕이 다르다. 2026-11-10 마이파이 "와이파이 비번, 아직도 불러 주세요?" 가 이 형식이다.
짙은 남색 바탕에 앱 색 두 가지(`accent` · `accent2`)가 모서리에서 번지고, 폰은 유리 테두리로 비스듬히 떠 있다.
폰 위에 그 기능을 한마디로 적은 흰 말풍선 칩(`callout`: SF Symbol + 글, 위치 `x` · `y` 는 0~1)이 뜬다. 쪽 표시는 점.

```
swiftc -parse-as-library -O glow.swift -o /tmp/cardnews-glow
/tmp/cardnews-glow <deck.json> <출력 폴더>
```

- `deck.json` 형식은 `glow-example.json`. 표지는 폰 한 대(`coverScreen` · `coverTop` · `coverCallout`).
- 크림 바탕(`feature.swift`)과 번갈아 쓰면 피드가 단조롭지 않다.

## 한 기능 깊이형 (앱 하나, 기능 하나를 풀어서) — 2026-11-12 부터 기본

2026-11-12 사용자 지시: 앞으로 카드뉴스는 **한 앱의 한 기능**을 풀어서 설명한다. 표지는 질문으로 열고,
읽는 사람이 "오, 유용하다 · 혹시 이런 거 아세요?" 하고 느끼게. 새 렌더러는 없다 — `feature.swift`(크림) 와
`glow.swift`(빛번짐) 를 번갈아 쓰고, 내용의 짜임만 다르다. 첫 편은 클립키보드 템플릿 "답장 문구, 이름만 바꿔 쓰고 있어요?"
(`decks/2026-11-12-클립키보드-템플릿.json`), 다음 편으로 쑥쑥용돈 저축 이자(`decks/2026-11-12-쑥쑥용돈-저축이자.json`)가 그려져 있다.

- 표지: `kicker` 는 "혹시 이런 거 아세요? · <앱>의 <기능>", `cover` 는 그 기능이 답이 되는 **질문** 한 줄(세 줄 이내).
- 기능 장 4장이 한 기능을 차례로 푼다: ① 왜 그런 일이 생기나(공감) → ② 이 기능이 하는 일 → ③ 그래서 무엇이 보이나(숫자 · 화면) → ④ 덤(같이 쓰는 것).
  `label` 은 번호 뒤 짧은 말, `headline` 은 두 줄, `text` 는 두 줄. 같은 화면을 `top` 만 달리해 두 번 써도 된다.
- 마지막 장 `outro` 는 그 기능이 바꾸는 한마디, `points` 는 앱 전체의 믿을 거리 세 줄.
- 앱 안에 **실제로 있는 숫자 · 문구**만 쓴다(소스 · 화면에서 확인). 기능 여러 개를 나열하지 않는다.
- 아이콘은 그 앱 `AppIcon.appiconset` 의 1024 PNG. 앱이 Icon Composer(`AppIcon.icon`)만 쓰면 레포의 옛 PNG 를 쓰지 말고
  App Store 에 올라간 그림을 받아 `decks/icons/<앱>-1024.png` 에 둔다
  (`curl "https://itunes.apple.com/lookup?id=<앱 id>&country=kr"` 의 `artworkUrl512` 에서 `512x512bb` 를 `1024x1024bb` 로).
- 덱은 `decks/YYYY-MM-DD-<앱>-<기능>.json` 으로 남긴다. 다음 편은 같은 앱이라도 다른 기능, 되도록 지난 2주에 안 다룬 앱.
