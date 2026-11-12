#!/bin/sh
# PMS 백업 — DB(pg_dump) + 첨부파일·Vault 키 파일(날짜별 스냅숏, 바뀌지 않은 파일은 하드링크)
#   setup/backup.sh                 바로 백업 (cron 매일 03:00)
#   setup/backup.sh --if-requested  관리 → 백업 화면의 [지금 백업] 요청이 있을 때만 (cron 1분마다)
# 결과: backup/db/db_<이름>.dump, backup/files/<이름>/{files,keys}, 상태는 backup/ctl/status.json · list.json (화면이 읽음)
# 보관: .env 의 BACKUP_KEEP_DAYS (기본 14일), 가장 최근 것은 항상 남김. .env 는 백업하지 않음(서버 밖으로 옮길 때 따로)
set -eu
# PMS_DIR · PMS_BACKUP_DIR 로 Redmine 폴더 · 백업 폴더를 바꿀 수 있음 (시험용)
cd "${PMS_DIR:-$(dirname "$0")/..}"
ROOT=$(pwd)
BK=${PMS_BACKUP_DIR:-$ROOT/backup}
CTL="$BK/ctl"
mkdir -p "$BK/db" "$BK/files" "$CTL"
chmod 700 "$BK/db" "$BK/files"
# 화면(컨테이너 redmine 사용자 999)이 요청 표시를 쓸 수 있게
chown 999:999 "$CTL" 2>/dev/null || true
chmod 755 "$CTL"

if [ "${1:-}" = "--if-requested" ]; then
  [ -f "$CTL/request" ] || exit 0
fi

# 동시에 하나만
exec 9>"$BK/.lock"
flock -n 9 || { echo "이미 백업 중"; exit 0; }

REQUESTED_BY=""
[ -f "$CTL/request" ] && REQUESTED_BY=$(head -c 60 "$CTL/request" | tr -cd 'A-Za-z0-9_.@-') && rm -f "$CTL/request"

KEEP=$(grep -s '^BACKUP_KEEP_DAYS=' .env | cut -d= -f2 | tr -cd '0-9')
KEEP=${KEEP:-14}
PROJ=${COMPOSE_PROJECT_NAME:-$(basename "$ROOT")}
NAME=$(date +%F_%H%M)
# 같은 이름(같은 분)의 백업이 있으면 다음 분까지 기다림 — 복원 직전 백업이 복원 대상을 덮어쓰지 않게
while [ -e "$BK/files/$NAME" ] || [ -e "$BK/db/db_$NAME.dump" ]; do sleep 5; NAME=$(date +%F_%H%M); done
START=$(date +%s)
STEP=""
date '+%F %T' > "$CTL/running"

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }

# 백업 목록(화면용) — 이름 · DB 크기 · 첨부 수
write_list() {
  {
    printf '['
    first=1
    for d in $(ls -1 "$BK/files" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' | sort -r); do
      dbf="$BK/db/db_$d.dump"
      dbs=0; [ -f "$dbf" ] && dbs=$(stat -c %s "$dbf")
      fc=$(cat "$BK/files/$d/.count" 2>/dev/null || echo 0)
      fs=$(cat "$BK/files/$d/.bytes" 2>/dev/null || echo 0)
      [ $first = 1 ] || printf ','
      printf '{"name":"%s","db_bytes":%s,"files":%s,"files_bytes":%s}' "$d" "$dbs" "$fc" "$fs"
      first=0
    done
    printf ']'
  } > "$CTL/list.json.tmp" && mv "$CTL/list.json.tmp" "$CTL/list.json"
  chmod 644 "$CTL/list.json"
}

finish() {
  code=$?
  set +e
  END=$(date +%s)
  DISK=$(df -P "$BK" | awk 'NR==2 {print $4 * 1024}')
  USED=$(du -s -B1 "$BK/db" "$BK/files" 2>/dev/null | awk '{s+=$1} END {print s+0}')
  if [ $code = 0 ]; then OK=true; ERR=""; else OK=false; ERR="실패 단계: $STEP (종료 코드 $code)"; rm -rf "$BK/files/$NAME.tmp" "$BK/db/db_$NAME.dump.tmp"; fi
  printf '{"name":"%s","ok":%s,"error":"%s","started_at":"%s","seconds":%s,"db_bytes":%s,"files":%s,"files_bytes":%s,"disk_free":%s,"backup_used":%s,"keep_days":%s,"requested_by":"%s"}\n' \
    "$NAME" "$OK" "$(json_esc "$ERR")" "$(date -d @"$START" '+%F %T')" "$((END - START))" "${DB_BYTES:-0}" "${FILES:-0}" "${FILES_BYTES:-0}" "${DISK:-0}" "${USED:-0}" "$KEEP" "$REQUESTED_BY" > "$CTL/status.json"
  chmod 644 "$CTL/status.json"
  write_list
  rm -f "$CTL/running"
  echo "$(date '+%F %T') $NAME ok=$OK ${ERR} db=${DB_BYTES:-0}B files=${FILES:-0} $((END - START))s" >> "$BK/backup.log"
  exit $code
}
trap finish EXIT

# 1) DB — db 컨테이너의 pg_dump (서버 버전과 같음), 압축 형식
STEP="DB 덤프"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -Fc "$POSTGRES_DB"' > "$BK/db/db_$NAME.dump.tmp"
mv "$BK/db/db_$NAME.dump.tmp" "$BK/db/db_$NAME.dump"
chmod 600 "$BK/db/db_$NAME.dump"
DB_BYTES=$(stat -c %s "$BK/db/db_$NAME.dump")

# 2) 첨부파일 · Vault 키 파일 — 직전 스냅숏과 같은 파일은 하드링크
STEP="첨부파일 복사"
PREV=$(ls -1 "$BK/files" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$' | sort | tail -1 || true)
mkdir -p "$BK/files/$NAME.tmp"
for v in files keys; do
  SRC=$(docker volume inspect -f '{{.Mountpoint}}' "${PROJ}_$v")
  LINK=""
  [ -n "$PREV" ] && [ -d "$BK/files/$PREV/$v" ] && LINK="--link-dest=$BK/files/$PREV/$v"
  rsync -a --delete $LINK "$SRC/" "$BK/files/$NAME.tmp/$v/"
done
FILES=$(find "$BK/files/$NAME.tmp/files" -type f | wc -l)
FILES_BYTES=$(du -s -B1 --apparent-size "$BK/files/$NAME.tmp/files" | cut -f1)
echo "$FILES" > "$BK/files/$NAME.tmp/.count"
echo "$FILES_BYTES" > "$BK/files/$NAME.tmp/.bytes"
mv "$BK/files/$NAME.tmp" "$BK/files/$NAME"

# 3) 보관 기간이 지난 백업 삭제 (가장 최근 것은 항상 남김)
STEP="오래된 백업 정리"
CUT=$(date -d "-$KEEP days" +%F)
LATEST=$NAME
for d in $(ls -1 "$BK/files" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}$'); do
  if [ "${d%_*}" \< "$CUT" ] && [ "$d" != "$LATEST" ]; then rm -rf "$BK/files/$d"; fi
done
for f in $(ls -1 "$BK/db" | grep -E '^db_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{4}\.dump$'); do
  n=${f#db_}; n=${n%.dump}
  if [ "${n%_*}" \< "$CUT" ] && [ "$n" != "$LATEST" ]; then rm -f "$BK/db/$f"; fi
done
rm -rf "$BK/files/"*.tmp "$BK/db/"*.tmp 2>/dev/null || true
STEP=""
