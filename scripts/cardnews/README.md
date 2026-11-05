# 카드뉴스 그리기 (인스타)

앱 마케팅 칸의 카드뉴스 뷰를 떼어 와 1080×1350 PNG 로 그린다.

```
swiftc -parse-as-library -O render.swift -o /tmp/cardnews-render
/tmp/cardnews-render <slides.json> <unused> <아이콘 file:// URL> <앱 이름> <출력 폴더>
```

- `slides.json` 형식은 `example.json`. `screen` 은 그 앱 레포 `docs/screenshots/raw/...` 의 실제 화면.
- 마지막 장에 `App Store 에서 "<앱 이름>" 검색` 이 자동으로 붙는다.
- 인스타 업로드는 JPG 로 바꿔서 (`sips -s format jpeg`).
