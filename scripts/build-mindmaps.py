#!/usr/bin/env python3
# 앱마다 "문제 → 타겟 → 솔루션 → 결제까지" 마인드맵 HTML 을 만든다.
#
#   ./scripts/build-mindmaps.py
#
# 원본은 `scripts/mindmaps/<프로젝트 키>.json` 이고, 결과는 앱 안
# `FeedbackHubViewer/Mindmaps/mindmap-<프로젝트 키>.html` 이다. 설계 칸이 앱에 든 이 사본을
# 열기 때문에 폰 · 패드에서도, 오프라인에서도 보인다. 글을 고칠 때는 JSON 을 고치고 다시 돌린다.
#
# 설계 칸의 전체 목록은 `Mindmaps/mindmaps.json`(키 → 이름)을 읽는다. 허브에 아직 안 잡힌
# 앱도 거기서 보인다.
#
# 한 장은 외부 글꼴 · 스크립트 없이 혼자 열린다(WKWebView 가 파일로 연다).

import html
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "scripts" / "mindmaps"
OUTPUT = ROOT / "FeedbackHubViewer" / "Mindmaps"
STEPS = ["발견", "스토어 페이지", "첫 실행", "첫 성공", "다시 찾기", "결제 벽", "결제"]


def e(text):
    return html.escape(str(text), quote=True)


def leaf(text, cls=""):
    return f'<li><div class="node {cls}">{e(text)}</div></li>'


def branch(label, cls, children):
    return (f'<li><div class="node branch {cls}">{e(label)}</div>'
            f'<ul>{"".join(children)}</ul></li>')


def lead(text, children, cls=""):
    """굵은 줄 하나 밑에 잎들."""
    inner = f'<ul>{"".join(leaf(c) for c in children)}</ul>' if children else ""
    return f'<li><div class="node lead {cls}">{e(text)}</div>{inner}</li>'


def page(d):
    p, t, s, pay = d["problem"], d["target"], d["solution"], d["payment"]
    steps = {j["step"]: j for j in d["journey"]}
    missing = [name for name in STEPS if name not in steps]
    if missing:
        raise ValueError(f'{d["project"]}: journey 에 {missing} 단계가 없다')

    target_children = [lead(t["who"], t.get("moments", []))]
    if t.get("notFor"):
        target_children.append(leaf("노리지 않는 사람 · " + t["notFor"], "muted"))

    journey = []
    for i, name in enumerate(STEPS, 1):
        j = steps[name]
        cls = "pay" if name == "결제" else ("wall" if name == "결제 벽" else "")
        label = f'{i} {name} · {j["what"]}'
        journey.append(lead(label, j.get("details", []), cls))

    tree = (
        f'<ul class="tree"><li><div class="node root">{e(d["name"])}'
        f'<small>{e(d["tagline"])}</small></div><ul>'
        + branch("문제", "b1", [lead(p["statement"], p.get("pains", []))])
        + branch("타겟", "b2", target_children)
        + branch("솔루션", "b3", [lead(s["core"], s.get("features", []))])
        + branch("결제까지", "b4", journey)
        + "</ul></li></ul>"
    )

    products = "".join(f"<li>{e(x)}</li>" for x in pay.get("products", [])) or "<li>상품 없음</li>"
    proposals = "".join(f"<li>{e(x)}</li>" for x in d.get("proposals", []))
    sources = "".join(f"<li>{e(x)}</li>" for x in d.get("sources", []))

    return f"""<!doctype html>
<html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{e(d["name"])} 결제까지 마인드맵</title>
<style>{CSS}</style></head><body><main class="wrap">
<header>
  <p class="eyebrow">문제 → 타겟 → 솔루션 → 결제</p>
  <h1>{e(d["name"])}</h1>
  <p class="lede">{e(d["tagline"])}</p>
  <p><span class="pill">{e(pay["model"])}</span></p>
</header>
<section class="cards">
  <article class="card c1"><h2>문제 정의</h2><p>{e(p["statement"])}</p></article>
  <article class="card c2"><h2>타겟</h2><p>{e(t["who"])}</p></article>
  <article class="card c3"><h2>솔루션</h2><p>{e(s["core"])}</p></article>
</section>
<section><h2>마인드맵</h2><div class="map">{tree}</div></section>
<section class="cards">
  <article class="card c4"><h2>결제하는 순간</h2>
    <dl><dt>방식</dt><dd>{e(pay["model"])}</dd>
    <dt>무료로 되는 것</dt><dd>{e(pay.get("freeLimit", "미확인"))}</dd>
    <dt>결제 버튼이 보일 때</dt><dd>{e(pay.get("trigger", "미확인"))}</dd>
    <dt>상품</dt><dd><ul>{products}</ul></dd></dl>
  </article>
  <article class="card proposal"><h2>제안 <span>확인된 사실 아님</span></h2><ul>{proposals}</ul></article>
</section>
<footer><p class="eyebrow">근거 파일</p><ul class="sources">{sources}</ul></footer>
</main></body></html>
"""


CSS = """
:root{--bg:#f5f5f2;--paper:#fff;--fg:#1b1d1c;--muted:#5f6662;--line:#cfd4d0;
--c1:#c8463b;--c2:#2f6fcf;--c3:#7a4fc4;--c4:#1f8a5b;--wall:#c98a12;color-scheme:light;
--font:-apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo",system-ui,sans-serif;--mono:ui-monospace,Menlo,monospace}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#141716;--paper:#1d211f;--fg:#e8ece9;
--muted:#a1aaa4;--line:#3a423e;--c1:#f07a6f;--c2:#6ea2ef;--c3:#ad8bef;--c4:#4cc38a;--wall:#e7b24a;color-scheme:dark}}
:root[data-theme="dark"]{--bg:#141716;--paper:#1d211f;--fg:#e8ece9;--muted:#a1aaa4;--line:#3a423e;
--c1:#f07a6f;--c2:#6ea2ef;--c3:#ad8bef;--c4:#4cc38a;--wall:#e7b24a;color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 var(--font)}
.wrap{max-width:1280px;margin:0 auto;padding:32px max(16px,env(safe-area-inset-left)) 64px;display:grid;gap:36px}
header{display:grid;gap:8px}
h1{font-size:30px;line-height:1.2;margin:0}
h2{font-size:18px;margin:0 0 10px}
p{margin:0}
.eyebrow{font:12px var(--mono);letter-spacing:.06em;color:var(--muted)}
.lede{color:var(--muted);font-size:16px;max-width:60ch}
.pill{display:inline-block;font-size:13px;padding:2px 10px;border-radius:99px;border:1px solid var(--c4);color:var(--c4)}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:12px}
.card{background:var(--paper);border:1px solid var(--line);border-top:4px solid var(--c);border-radius:10px;padding:16px}
.c1{--c:var(--c1)}.c2{--c:var(--c2)}.c3{--c:var(--c3)}.c4{--c:var(--c4)}
.card ul{margin:0;padding-left:18px;display:grid;gap:4px}
.proposal{--c:var(--line);border-style:dashed;border-top-style:solid}
.proposal h2 span{font:12px var(--mono);color:var(--muted);font-weight:400;margin-left:6px}
dl{margin:0;display:grid;gap:4px}
dt{font-size:13px;color:var(--muted)}
dd{margin:0 0 6px}
.map{background:var(--paper);border:1px solid var(--line);border-radius:12px;padding:20px;overflow-x:auto}
/* 가로 트리: 줄기는 왼쪽, 가지는 오른쪽으로 뻗는다 */
.tree,.tree ul{list-style:none;margin:0;padding:0}
.tree ul{display:flex;flex-direction:column;justify-content:center;position:relative;padding-left:24px}
.tree li{display:flex;align-items:center;position:relative;padding:3px 0 3px 24px}
.tree>li{padding-left:0}
.tree ul::before{content:"";position:absolute;left:0;top:50%;width:24px;border-top:2px solid var(--line)}
.tree li::before{content:"";position:absolute;left:0;top:50%;width:24px;border-top:2px solid var(--line)}
.tree li::after{content:"";position:absolute;left:0;top:0;bottom:0;border-left:2px solid var(--line)}
.tree li:first-child::after{top:50%}
.tree li:last-child::after{bottom:50%}
.tree li:only-child::after,.tree>li::before,.tree>li::after{display:none}
.node{flex:none;max-width:280px;background:var(--bg);border:1px solid var(--line);border-radius:8px;padding:6px 10px;font-size:14px}
.root{background:var(--fg);color:var(--bg);border:none;font-size:20px;font-weight:700;max-width:220px;padding:14px 16px}
.root small{display:block;font-size:13px;font-weight:400;opacity:.8;margin-top:4px}
.branch{color:#fff;border:none;font-weight:700;font-size:16px;padding:8px 14px}
.b1{background:var(--c1)}.b2{background:var(--c2)}.b3{background:var(--c3)}.b4{background:var(--c4)}
.lead{font-weight:600;background:var(--paper)}
.muted{color:var(--muted)}
.wall{border:2px solid var(--wall)}
.pay{background:var(--c4);color:#fff;border:none}
footer{display:grid;gap:6px}
.sources{margin:0;padding-left:18px;font:12px var(--mono);color:var(--muted)}
/* 좁은 화면: 들여쓴 세로 목록 */
@media (max-width:760px){
.map{padding:14px}
.tree ul{display:block;padding-left:0;margin-left:12px}
.tree li{display:block;padding:4px 0 4px 18px}
.tree ul::before{display:none}
.tree li::before{top:20px;width:14px}
.tree li::after,.tree li:first-child::after{top:0;bottom:auto;height:100%}
.tree li:last-child::after{height:20px}
.tree li:only-child::after{display:block;height:20px}
.node{display:inline-block;max-width:100%}
}
"""


def main():
    files = sorted(SOURCE.glob("*.json"))
    if not files:
        sys.exit(f"{SOURCE} 에 JSON 이 없다")
    OUTPUT.mkdir(exist_ok=True)
    index = {}
    for f in files:
        d = json.loads(f.read_text(encoding="utf-8"))
        out = OUTPUT / f'mindmap-{d["project"]}.html'
        out.write_text(page(d), encoding="utf-8")
        index[d["project"]] = d["name"]
        print(f"✅ {d['name']} → {out.relative_to(ROOT)}")
    (OUTPUT / "mindmaps.json").write_text(
        json.dumps(index, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
