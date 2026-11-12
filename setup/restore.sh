#!/bin/sh
# PMS 복원 — backup.sh 로 만든 백업으로 DB · 첨부파일 · Vault 키 파일을 되돌림
#   setup/restore.sh                 백업 목록 보기
#   setup/restore.sh <이름>          예: setup/restore.sh 2026-11-12_0300  (DB + 첨부·키)
#   setup/restore.sh <이름> --db     DB 만 / --files  첨부·키만
# 순서: 확인 입력 → 지금 상태를 한 번 더 백업 → Redmine 멈춤 → DB 복원 → 첨부·키 되돌림 → Redmine 시작
# 새 서버에서는: README 설치 1~3단계(같은 .env) → backup/ 폴더를 옮겨 놓고 이 스크립트 실행
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
# PMS_DIR · PMS_BACKUP_DIR 로 Redmine 폴더 · 백업 폴더를 바꿀 수 있음 (시험용)
cd "${PMS_DIR:-$(dirname "$0")/..}"
ROOT=$(pwd)
BK=${PMS_BACKUP_DIR:-$ROOT/backup}
PROJ=${COMPOSE_PROJECT_NAME:-$(basename "$ROOT")}

if [ $# -lt 1 ]; then
  echo "백업 목록 (이름 · DB · 첨부 수):"
  for d in $(ls -1 "$BK/files" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' | sort -r); do
    printf '  %s  %s  %s\n' "$d" "$(du -h "$BK/db/db_$d.dump" 2>/dev/null | cut -f1)" "$(cat "$BK/files/$d/.count" 2>/dev/null)"
  done
  echo "사용: setup/restore.sh <이름> [--db|--files]"
  exit 0
fi

NAME=$1
MODE=${2:-all}
echo "$NAME" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' || { echo "이름 형식: YYYY-MM-DD_HHMM"; exit 1; }
DUMP="$BK/db/db_$NAME.dump"
SNAP="$BK/files/$NAME"
[ "$MODE" = "--files" ] || [ -f "$DUMP" ] || { echo "DB 백업이 없습니다: $DUMP"; exit 1; }
[ "$MODE" = "--db" ] || [ -d "$SNAP/files" ] || { echo "첨부 백업이 없습니다: $SNAP"; exit 1; }

echo "[$NAME] 백업으로 되돌립니다 ($MODE). 지금 데이터는 이 시점으로 바뀝니다 (복원 전에 지금 상태를 한 번 더 백업합니다)."
printf '계속하려면 RESTORE 를 입력하세요: '
read -r answer
[ "$answer" = "RESTORE" ] || { echo "취소했습니다"; exit 1; }

echo "[1/4] 지금 상태 백업"
sh "$HERE/backup.sh"

echo "[2/4] Redmine 멈춤"
docker compose stop redmine

if [ "$MODE" != "--files" ]; then
  echo "[3/4] DB 복원"
  docker compose exec -T db sh -c 'pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner --single-transaction' < "$DUMP"
fi
if [ "$MODE" != "--db" ]; then
  echo "[3/4] 첨부파일 · Vault 키 되돌림"
  for v in files keys; do
    DST=$(docker volume inspect -f '{{.Mountpoint}}' "${PROJ}_$v")
    rsync -a --delete "$SNAP/$v/" "$DST/"
  done
fi

echo "[4/4] Redmine 시작"
docker compose start redmine
[ -n "${PMS_SKIP_WAIT:-}" ] && { echo "[완료] $NAME 으로 복원했습니다"; exit 0; }
printf '[대기] '
i=0; until [ "$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:${REDMINE_PORT:-3000}/login")" = 200 ]; do
  i=$((i+1)); [ $i -gt 60 ] && { echo '시간 초과 — docker compose logs redmine 확인'; exit 1; }; printf '.'; sleep 3
done; echo ' 정상'
echo "[완료] $NAME 으로 복원했습니다"
