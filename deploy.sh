#!/bin/sh
# 서버 배포: GitHub 최신 커밋을 받아 바뀐 부분에 맞춰 반영
# 사용: cd /root/redmine && ./deploy.sh
set -eu
cd "$(dirname "$0")"

# 관리 > 백업 화면이 쓰는 상태 폴더 (컨테이너 redmine 사용자가 요청 표시를 씀)
mkdir -p backup/ctl && chown 999:999 backup/ctl

OLD=$(git rev-parse HEAD)
git pull --ff-only -q
NEW=$(git rev-parse HEAD)
if [ "$OLD" = "$NEW" ]; then echo "이미 최신입니다 ($(git log --oneline -1))"; exit 0; fi

echo "[변경] $(git log --oneline "$OLD..$NEW" | wc -l)개 커밋"
git log --oneline "$OLD..$NEW" | sed 's/^/  /'
CHANGED=$(git diff --name-only "$OLD" "$NEW")

if echo "$CHANGED" | grep -qE '^(Dockerfile|compose\.yaml|plugins/db_manage/Gemfile|plugins/menu_tree/Gemfile|plugins/vault_ko/(build\.rb|snippets/.*))$'; then
  echo "[이미지·구성 변경] 다시 빌드합니다"
  docker compose up -d --build
else
  echo "[재시작] 테마·플러그인 반영"
  docker compose restart redmine
fi

printf '[대기] '
i=0; until [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${REDMINE_PORT:-3000}/login")" = 200 ]; do
  i=$((i+1)); [ $i -gt 60 ] && { echo '시간 초과 — docker compose logs redmine 확인'; exit 1; }; printf '.'; sleep 3
done; echo ' 정상'

if echo "$CHANGED" | grep -q '^setup/\(seed\.yml\|welcome\.md\|apply_settings\.rb\)$'; then
  echo "[기준 설정 변경] apply_settings.rb 실행"
  docker compose exec -T redmine sh -c 'SECRET_KEY_BASE=$REDMINE_SECRET_KEY_BASE bundle exec rails runner setup/apply_settings.rb' 2>&1 | grep -v ostruct
fi
echo "[완료] $(git log --oneline -1)"
