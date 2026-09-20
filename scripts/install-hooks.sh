#!/bin/bash
# 이 리포의 git 훅을 켠다. **한 번만** 돌리면 된다.
#
#   ./scripts/install-hooks.sh
#
# 훅 본체는 `.githooks/` 에 있고 git 이 추적한다. `.git/hooks/` 에 직접 두지 않는
# 까닭은 거기 있는 파일은 **커밋되지 않아서** 다시 클론하면 사라지고, 리뷰에도
# 안 보이기 때문이다. 대신 git 에게 어디를 볼지 한 번 알려 줘야 한다(core.hooksPath는
# 각 기기의 로컬 설정이라 커밋으로 따라가지 않는다).
#
# 끄려면: git config --unset core.hooksPath

set -euo pipefail
cd "$(dirname "$0")/.."

chmod +x .githooks/* 2>/dev/null || true
git config core.hooksPath .githooks

echo "✓ 훅을 켰습니다 (core.hooksPath = .githooks)"
echo "  커밋할 때마다 스펙이 앱과 어긋났는지 검사합니다."
echo "  끄려면: git config --unset core.hooksPath"
