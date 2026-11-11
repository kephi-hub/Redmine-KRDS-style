# Redmine KRDS Style

Redmine 6.1.6 + Vault(접속정보) 플러그인을 **KRDS(대한민국 정부 디자인 시스템) 스타일**과 한국어 운영 설정으로 묶은 Docker Compose 구성입니다.
Jenkins 배포 연동·용어사전·DB 관리 플러그인이 함께 들어 있습니다. 데이터는 포함하지 않으며, 새 서버에서 아래 순서대로 설치하면 같은 화면·설정으로 시작합니다. 데스크톱과 모바일(반응형) 화면을 모두 지원합니다.

## 주요 기능
| 영역 | 내용 |
|---|---|
| 디자인 | KRDS 색상·간격 토큰, Pretendard GOV 글꼴, 반응형(모바일 카드형 목록·오른쪽 메뉴 패널), 박스형 설정 탭, 관리 카드 메뉴, 하단 버튼 오른쪽 정렬(취소는 테두리 버튼) |
| 일감 · 작업내역 | 검색조건 접기·적용 개수 표시, 더보기(…) 메뉴, 작업내역 오전/오후 12시간제, 사용자 시간대 서울 |
| 문서 | 게시판형 목록, 범주 배지·범주/제목 검색, 상세 화면, 편집할 때 첨부 추가·삭제 |
| 게시판 · 뉴스 · 파일 | 게시판 목록·글 목록·글 상세(상단 고정·잠금 배지, 답글, 취소 버튼), 뉴스·파일 제목 검색 |
| 접속정보 (Vault) | 한국어 화면, 검색·선택 삭제, 비밀번호 가림·복사, 관리자가 정하는 유형 목록(관리 → 접속정보(Vault) → 유형 관리) |
| Jenkins 배포 | 프로젝트 "배포" 탭에서 실행(Jenkins 매개변수 선택, 운영 배포 식별자 확인), 진행 중 스피너·진행바, 이력(커밋 수·리비전) |
| 용어사전 | 프로젝트 "용어사전" 탭(프로젝트 용어 + 전사 공통 용어), 관리 → 공통 용어사전, 용어·영문명·약어·분류 검색, CSV 가져오기·내보내기(엑셀 호환), 위키·일감 본문 `{{term(용어)}}` |
| DB 관리 | 관리 → DB 서버(MariaDB·MySQL, PostgreSQL / MS SQL·Oracle 준비 중, 비밀번호 암호화, 연결 시험), 프로젝트 "DB" 탭: 테이블·컬럼·키 조회, 테이블 정의서(엑셀), 개발/운영 비교, 용어사전 점검 |
| 역할 · 권한 | 역할 4종(PM/PL · 개발자 · 디자이너 · 조회자), 완료·거절은 PM/PL 만, 보류는 작업자도 선택, 프로젝트 비공개(구성원만 보임), 관리 → 권한 한눈에 보기 · 업무흐름 설정 · 항목 편집 권한 설정 |
| 운영 설정 | 역할 권한·업무흐름 기본값·일감 유형·상태·안내문 등 기준 설정을 `setup/seed.yml` 로 재현 |

## 화면
> 아래 화면의 프로젝트·사용자·접속정보·Jenkins 작업은 모두 캡처용 예시 데이터입니다.

| 일감 목록 · 더보기(…) 메뉴 | 일감 상세 |
|---|---|
| ![일감 목록](docs/screenshots/02_issues.png) | ![일감 상세](docs/screenshots/03_issue_show.png) |
| **일감 등록 — 하단 버튼 오른쪽 정렬** | **작업내역 — 오전/오후 12시간제** |
| ![일감 등록](docs/screenshots/04_issue_new.png) | ![작업내역](docs/screenshots/09_activity.png) |
| **문서 목록 — 범주·제목 검색 · 배지** | **문서 상세 · 첨부파일** |
| ![문서 목록](docs/screenshots/05_documents.png) | ![문서 상세](docs/screenshots/06_document_show.png) |
| **게시판 글 목록 — 상단 고정 · 잠금 배지** | **게시판 글 상세 · 답글** |
| ![게시판 글 목록](docs/screenshots/13_board.png) | ![게시판 글 상세](docs/screenshots/14_topic.png) |
| **배포 — 환경 카드 · 진행바 · 이력** | **프로젝트 설정 — 박스형 탭 · 게시판 관리** |
| ![배포](docs/screenshots/15_deploys.png) | ![프로젝트 설정](docs/screenshots/10_settings.png) |
| **접속정보(Vault) 목록 — 검색 · 선택 삭제** | **접속정보 상세 — 비밀번호 가림 · 복사** |
| ![접속정보 목록](docs/screenshots/07_keys.png) | ![접속정보 상세](docs/screenshots/08_key_show.png) |
| **뉴스 — 게시판형 목록 · 제목 검색** | **파일 — 파일명 검색** |
| ![뉴스](docs/screenshots/11_news.png) | ![파일](docs/screenshots/12_files.png) |

**모바일 (900px 미만)** — 흰 상단 바, 카드형 목록, 아이콘 버튼, 오른쪽 메뉴 패널

| 일감 목록 | 일감 상세 | 메뉴 | 프로젝트 설정 | 배포 |
|---|---|---|---|---|
| ![모바일 일감 목록](docs/screenshots/m1_issues.png) | ![모바일 일감 상세](docs/screenshots/m2_issue.png) | ![모바일 메뉴](docs/screenshots/m3_menu.png) | ![모바일 프로젝트 설정](docs/screenshots/m4_settings.png) | ![모바일 배포](docs/screenshots/m5_deploys.png) |

<details><summary>로그인 화면</summary>

![로그인](docs/screenshots/01_login.png)
</details>

## 구성
| 경로 | 내용 |
|---|---|
| `Dockerfile` | `redmine:6.1.6` 공식 이미지 + Vault 0.10.5 (커밋 고정) |
| `compose.yaml` | PostgreSQL 17 + Redmine, 데이터는 Docker 볼륨(`db_data`, `files`, `keys`) |
| `themes/krds/` | KRDS 테마 (색상·간격 토큰, 버튼·드롭다운·목록·상세·폼, 박스형 설정 탭, 관리 카드 메뉴, 하단 버튼 오른쪽 정렬, 검색조건 접기 스크립트) |
| `plugins/krds_ui/` | 문서·게시판 화면 마크업, 첨부 PDF 미리보기, 문서 범주 검색조건·배지, 문서·뉴스·파일 제목 검색, 문서 편집 시 첨부 추가·삭제, 작업내역 오전·오후 12시간제 표시, 한글 이름 아바타(이름 2자), 누락 번역 보충 |
| `plugins/access_guide/` | 관리 → 권한 한눈에 보기(역할 × 영역을 관리/작성/보기/없음으로 요약, 사용자 × 프로젝트 역할표), 업무흐름 설정(역할마다 전환표 하나를 여러 일감 유형에 적용, 기본 "업무흐름" 메뉴 대체), 항목 편집 권한 설정(상태 × 항목을 편집·읽기 전용·필수로) |
| `plugins/jenkins_deploy/` | Jenkins 배포 연동 — 프로젝트 "배포" 탭에서 배포 실행·진행 상태·이력 (Jenkins 기본 API, 토큰 암호화 저장) |
| `plugins/glossary/` | 용어사전 — 용어·영문명·약어(컬럼명)·데이터 타입·정의, 프로젝트/공통 구분, CSV 가져오기(UTF-8·CP949)·내보내기, 위키 매크로 |
| `plugins/db_manage/` | DB 관리 — DB 서버 접속정보(암호화), 프로젝트별 개발·운영 DB 연결, 읽기 전용 메타데이터 조회, 테이블 정의서 xlsx, 스키마 비교, 용어 점검 (MariaDB 드라이버는 공식 이미지에 포함된 mysql2 를 플러그인 Gemfile 로 사용) |
| `plugins/vault_types/` | 접속정보 유형 관리 — 유형 이름·입력 방식(비밀번호·SFTP·키 파일)·순서를 관리 화면에서 정함, 접속정보에는 유형 번호만 추가 |
| `plugins/vault_ko/` | Vault 한국어 번역 + 화면 개선 규칙(`build.rb`). 이미지 빌드 때 원본 화면에 적용 (검색창, 선택 삭제, 비밀번호 가림, http 복사, 유형 선택칸·유형 표시·유형 관리 카드 연결) |
| `setup/` | 기준 설정(`seed.yml`), 초기화면 안내문(`welcome.md`), 적용 스크립트, cron 예시 |
| `config/configuration.yml` | 암호화 키를 `.env` 에서 읽음 (파일에 비밀값 없음) |

## 설치 (Rocky Linux 9 기준)
### 1. Docker 설치 (서버당 1회)
```bash
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo systemctl enable --now docker
sudo firewall-cmd --permanent --add-port=3000/tcp && sudo firewall-cmd --reload
```

### 2. 내려받기 · 비밀값 준비
```bash
git clone <저장소 주소> redmine && cd redmine
cp .env.example .env && chmod 600 .env
# .env 의 빈 값 채우기 — openssl rand -hex 32 (SYS_API_KEY 는 -hex 20)
```
> `.env` 는 Git 에 올라가지 않습니다. **`REDMINE_CIPHER_KEY` 를 잃으면 저장된 접속정보를 복구할 수 없으니** 안전한 곳에 따로 보관하세요.

### 3. 실행 · 기본 데이터 · 기준 설정
```bash
docker compose up -d --build
docker compose logs -f redmine          # "Listening on" 이 나오면 Ctrl+C
docker compose exec redmine sh -c 'bundle exec rake redmine:load_default_data REDMINE_LANG=ko'
docker compose exec redmine sh -c 'bundle exec rails runner setup/apply_settings.rb'
```
`apply_settings.rb` 는 테마·한국어·시간대(서울)·이름 표시(성이름)·첨부 1GB·커밋 키워드·역할 권한·안내문 등을 적용합니다. 시간대를 지정하지 않은 계정은 서울로 맞춥니다. 여러 번 실행해도 결과가 같습니다.

### 4. 커밋 자동 가져오기 (선택)
`setup/cron.example` 의 `KEY` 를 `.env` 의 `REDMINE_SYS_API_KEY` 로 바꿔 `/etc/cron.d/redmine_fetch` 로 저장하고 `chmod 600`.

### 5. 접속
`http://<서버IP>:3000` — 초기 계정 **admin / admin** (로그인 후 즉시 변경)

## 수정 · 배포
수정 → 커밋 → push 후 서버에서 **`cd /root/redmine && ./deploy.sh`** 한 줄이면 됩니다. 바뀐 파일을 보고 알아서 처리합니다.

| 바꾸는 것 | deploy.sh 가 하는 일 |
|---|---|
| 테마 CSS·JS, 플러그인 화면, 번역 | Redmine 재시작 |
| 플러그인 DB 변경 (`plugins/*/db/migrate`) | 재시작 때 자동 반영 (`REDMINE_PLUGINS_MIGRATE`) |
| 기준 설정 (`setup/seed.yml` · `welcome.md`) | 재시작 + `apply_settings.rb` 실행 |
| Redmine / Vault 버전 (`Dockerfile`, `compose.yaml`) | 이미지 다시 빌드 (브랜치에서 먼저 시험 권장) |

> **관리 화면에서 바꾼 기준 설정은 `setup/seed.yml` 에도 반영하세요.** 역할 권한·일감 유형·사이트 제목 등을 화면에서만 바꾸면, 다음에 `seed.yml`·`welcome.md` 가 바뀌는 배포 때 `apply_settings.rb` 가 다시 적용되면서 원래 값으로 돌아갑니다.

서버는 GitHub 저장소의 읽기 전용 Deploy key 로 받아옵니다 (`~/.ssh/config` 의 `Host github-redmine`).
서버에서 파일을 직접 고치지 마세요 — 다음 배포 때 `git pull` 이 멈춥니다.

- Vault 화면은 이미지 빌드 중 `plugins/vault_ko/build.rb` 가 원본 화면을 고쳐 만듭니다. Vault 버전을 올렸을 때 원본 문구가 바뀌어 맞지 않으면 `[못 찾음]` 을 출력하고 빌드가 멈춥니다.
- 글꼴(Pretendard GOV)은 공식 배포본을 jsDelivr CDN 으로 불러옵니다. 인터넷이 안 되는 서버에서는 시스템 글꼴(맑은 고딕 등)로 보입니다.
- 반응형: 모바일 퍼스트 — 기본 규칙은 모바일 기준, 데스크톱 전용 배치는 `application.css` 끝의 `@media (min-width:900px)` 에 둡니다. Redmine 의 `responsive.css` 가 테마보다 뒤에 로드되므로 모바일에서 덮어쓸 규칙에는 `#wrapper` 를 붙여 우선순위를 높입니다.
- CSS 작성 규칙: 규칙은 한 줄, 클래스명은 언더바(`_`)로 최대 2단어, 속성 순서는 display → position → flex → 크기 → 여백 → 테두리 → 배경 → 글꼴 → 색. Redmine 기본 선택자(`#main-menu` 등)는 예외입니다.

## Jenkins 배포 연동
Jenkins 쪽은 플러그인 설치 없이 **배포 전용 계정 + API 토큰**만 준비합니다 (배포 작업의 Read·Build 권한만 권장).

1. **관리 → Jenkins 서버**: 주소·계정·API 토큰 등록 후 [연결 시험] (토큰은 `REDMINE_CIPHER_KEY` 로 암호화 저장, 화면에 다시 표시하지 않음)
2. **관리 → 역할 및 권한**: "배포" 항목의 권한 지정 — 배포 이력 보기 / 배포 실행 / 운영 배포 실행 / 배포 설정 관리
3. **프로젝트 → 설정 → 모듈**에서 "배포" 켜기 → **설정 → 배포** 탭에서 환경(개발서버·운영서버 등)별 Jenkins 작업 경로·기본 매개변수(확인창 초기값, 예: `DEPLOY_PROD=true`) 지정
4. **프로젝트 → 배포** 탭에서 [배포 실행] — 확인창에서 Jenkins 작업의 매개변수를 체크박스·선택 목록·입력칸으로 선택, 운영 환경은 프로젝트 식별자를 입력해야 실행. 진행 중에는 스피너와 진행바(Jenkins 예상 소요 시간 기준)를 보여 주고 끝나면 자동 갱신

- Jenkins 에 정의된 매개변수만 전달하고(비밀번호 매개변수는 표시·전달하지 않음), 선택 목록은 Jenkins 선택지만 허용합니다.
- `REDMINE_USER`·`REDMINE_RUN_ID` 를 정의해 두면 실행자와 기록 번호를 자동으로 받습니다. 초기화면 안내문에 단계별 연결 가이드가 있습니다.
- 배포 이력의 **변경 내역** 칸은 Jenkins 빌드에 포함된 커밋 수·최신 리비전·메시지를 보여 줍니다(전체 보기로 목록 펼침, 리비전은 Redmine 저장소 화면으로 연결). 변경이 없는 빌드는 그 시점 Redmine 저장소의 최신 리비전을 보여 줍니다.
- Redmine 서버(Docker 컨테이너)에서 Jenkins 주소로 접속할 수 있어야 합니다. DB 테이블은 컨테이너 시작 때 자동 생성됩니다.

## 용어사전
1. **프로젝트 → 설정 → 모듈**에서 "용어사전" 켜기 → 프로젝트 메뉴에 **용어사전** 탭이 생깁니다.
2. 모든 프로젝트가 함께 쓰는 용어는 **관리 → 공통 용어사전**에 등록합니다(관리자만). 프로젝트 화면에는 `공통` 배지로 함께 보입니다.
3. 엑셀로 정리한 용어는 [가져오기]로 올립니다. 머리줄 `용어,영문명,약어,분류,데이터타입,길이,정의,비고` (용어만 필수, 'CSV UTF-8'·'CSV(쉼표로 분리)' 모두 가능). [내보내기] 파일을 고쳐서 다시 올려도 됩니다.
4. 위키·일감 본문에 `{{term(고객번호)}}` 라고 쓰면 `고객번호 (CUST_NO)` 로 표시되고 정의가 툴팁으로 나옵니다. 같은 이름이 있으면 프로젝트 용어가 우선입니다.
- 권한: 보기는 모든 역할, 등록·수정·삭제·가져오기는 PM/PL·개발자 (`setup/seed.yml`). DB 테이블은 컨테이너 시작 때 자동 생성됩니다.

## DB 관리
1. **관리 → DB 서버**: DB 종류·호스트·포트·DB 이름·계정·비밀번호 등록 후 [연결 시험] (비밀번호는 `REDMINE_CIPHER_KEY` 로 암호화 저장, 화면에 다시 표시하지 않음). **SELECT 권한만 있는 조회 전용 계정**을 권장합니다.
2. **프로젝트 → 설정 → 모듈**에서 "DB 관리" 켜기 → **설정 → DB** 탭에서 개발DB·운영DB 등을 추가 (서버 선택, 스키마 — 비워 두면 MariaDB 는 서버의 DB 이름, PostgreSQL 은 `public`)
3. **프로젝트 → DB** 탭: DB 별 테이블 목록(설명·컬럼 수·추정 행 수·용어 일치), 테이블을 누르면 컬럼·타입·NULL·기본값·PK/UK/FK·설명·용어사전 대조
   - **테이블 정의서**: 엑셀(xlsx) 2개 시트(테이블 목록 / 컬럼 정의)
   - **비교**: 두 DB 의 한쪽에만 있는 테이블, 컬럼 차이(타입·NULL·기본값·설명·키)
   - **용어 점검**: 컬럼명을 용어사전 약어와 대조(일치·타입 다름·미등록), 미등록 컬럼을 용어사전 가져오기 양식 CSV 로 내려받기
- 원격 DB 에는 읽기 전용 세션으로 접속해 테이블·컬럼 정보(메타데이터)만 읽습니다. 데이터 조회·변경 SQL 은 실행하지 않습니다.
- 권한: 보기 PM/PL·개발자, DB 연결 관리 PM/PL (`setup/seed.yml`). Redmine 컨테이너에서 DB 서버 주소·포트로 접속할 수 있어야 합니다.

## 백업
Git 에는 데이터가 없으므로 아래를 따로 백업합니다.
```bash
docker compose exec -T db pg_dump -U redmine -Fc redmine > backup/db_$(date +%F).dump
docker compose exec -T redmine tar czf - -C /usr/src/redmine files keys > backup/files_$(date +%F).tgz
cp .env backup/                                         # 암호화 키 포함
```
복원: 같은 `.env` 로 실행한 뒤 `pg_restore -U redmine -d redmine --clean` 과 파일 압축 해제.

## 라이선스 · 출처
이 저장소의 코드(테마·플러그인·설정 스크립트)는 **GNU GPL v2** 로 배포합니다 — [LICENSE](LICENSE)

- Redmine: GPL v2 — https://www.redmine.org
- Vault 플러그인: https://github.com/noshutdown-ru/vault — 저장소에 포함하지 않고 빌드 때 받아 씀
- Pretendard GOV 글꼴: SIL Open Font License 1.1 — https://github.com/orioncactus/pretendard (CDN 으로 불러옴, 저장소에 포함하지 않음)
- KRDS: 행정안전부 디자인 시스템 가이드 참고
