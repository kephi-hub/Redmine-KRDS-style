# Redmine KRDS Style

Redmine 6.1.6 + Vault(접속정보) 플러그인을 **KRDS(대한민국 정부 디자인 시스템) 스타일**과 한국어 운영 설정으로 묶은 Docker Compose 구성입니다.
데이터는 포함하지 않으며, 새 서버에서 아래 순서대로 설치하면 같은 화면·설정으로 시작합니다. 데스크톱과 모바일(반응형) 화면을 모두 지원합니다.

## 화면
> 아래 화면의 프로젝트·사용자·접속정보는 모두 캡처용 예시 데이터입니다.

| 일감 목록 · 더보기(…) 메뉴 | 일감 상세 |
|---|---|
| ![일감 목록](docs/screenshots/02_issues.png) | ![일감 상세](docs/screenshots/03_issue_show.png) |
| **일감 등록** | **작업내역** |
| ![일감 등록](docs/screenshots/04_issue_new.png) | ![작업내역](docs/screenshots/09_activity.png) |
| **문서 목록** | **문서 상세 · 첨부파일** |
| ![문서 목록](docs/screenshots/05_documents.png) | ![문서 상세](docs/screenshots/06_document_show.png) |
| **접속정보(Vault) 목록 — 검색 · 선택 삭제** | **접속정보 상세 — 비밀번호 가림 · 복사** |
| ![접속정보 목록](docs/screenshots/07_keys.png) | ![접속정보 상세](docs/screenshots/08_key_show.png) |
| **프로젝트 설정 — 박스형 탭 · 추가 버튼** | **뉴스 — 게시판 목록** |
| ![프로젝트 설정](docs/screenshots/10_settings.png) | ![뉴스](docs/screenshots/11_news.png) |
| **파일** | |
| ![파일](docs/screenshots/12_files.png) | |

**모바일 (900px 미만)** — 흰 상단 바, 카드형 일감 목록, 아이콘 버튼, 오른쪽 메뉴 패널

| 일감 목록 | 일감 상세 | 메뉴 | 프로젝트 설정 |
|---|---|---|---|
| ![모바일 일감 목록](docs/screenshots/m1_issues.png) | ![모바일 일감 상세](docs/screenshots/m2_issue.png) | ![모바일 메뉴](docs/screenshots/m3_menu.png) | ![모바일 프로젝트 설정](docs/screenshots/m4_settings.png) |

<details><summary>로그인 화면</summary>

![로그인](docs/screenshots/01_login.png)
</details>

## 구성
| 경로 | 내용 |
|---|---|
| `Dockerfile` | `redmine:6.1.6` 공식 이미지 + Vault 0.10.5 (커밋 고정) |
| `compose.yaml` | PostgreSQL 17 + Redmine, 데이터는 Docker 볼륨(`db_data`, `files`, `keys`) |
| `themes/krds/` | KRDS 테마 (색상·간격 토큰, 버튼·드롭다운·목록·상세·폼, 박스형 설정 탭, 관리 카드 메뉴, 검색조건 접기 스크립트) |
| `plugins/krds_ui/` | 문서 화면 마크업, 문서 편집 시 첨부 추가·삭제, 한글 이름 아바타(이름 2자), 누락 번역 보충 |
| `plugins/vault_ko/` | Vault 한국어 번역 + 화면 개선 규칙(`build.rb`). 이미지 빌드 때 원본 화면에 적용 (검색창, 선택 삭제, 비밀번호 가림, http 복사) |
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
`apply_settings.rb` 는 테마·한국어·이름 표시(성이름)·첨부 50MB·커밋 키워드·역할 권한·안내문 등을 적용합니다. 여러 번 실행해도 결과가 같습니다.

### 4. 커밋 자동 가져오기 (선택)
`setup/cron.example` 의 `KEY` 를 `.env` 의 `REDMINE_SYS_API_KEY` 로 바꿔 `/etc/cron.d/redmine_fetch` 로 저장하고 `chmod 600`.

### 5. 접속
`http://<서버IP>:3000` — 초기 계정 **admin / admin** (로그인 후 즉시 변경)

## 수정 · 배포
수정 → 커밋 → push 후 서버에서 **`cd /root/redmine && ./deploy.sh`** 한 줄이면 됩니다. 바뀐 파일을 보고 알아서 처리합니다.

| 바꾸는 것 | deploy.sh 가 하는 일 |
|---|---|
| 테마 CSS·JS, 플러그인 화면, 번역 | Redmine 재시작 |
| 기준 설정 (`setup/seed.yml` · `welcome.md`) | 재시작 + `apply_settings.rb` 실행 |
| Redmine / Vault 버전 (`Dockerfile`, `compose.yaml`) | 이미지 다시 빌드 (브랜치에서 먼저 시험 권장) |

서버는 GitHub 저장소의 읽기 전용 Deploy key 로 받아옵니다 (`~/.ssh/config` 의 `Host github-redmine`).
서버에서 파일을 직접 고치지 마세요 — 다음 배포 때 `git pull` 이 멈춥니다.

- Vault 화면은 이미지 빌드 중 `plugins/vault_ko/build.rb` 가 원본 화면을 고쳐 만듭니다. Vault 버전을 올렸을 때 원본 문구가 바뀌어 맞지 않으면 `[못 찾음]` 을 출력하고 빌드가 멈춥니다.
- 글꼴(Pretendard GOV)은 공식 배포본을 jsDelivr CDN 으로 불러옵니다. 인터넷이 안 되는 서버에서는 시스템 글꼴(맑은 고딕 등)로 보입니다.
- 반응형: 모바일 퍼스트 — 기본 규칙은 모바일 기준, 데스크톱 전용 배치는 `application.css` 끝의 `@media (min-width:900px)` 에 둡니다. Redmine 의 `responsive.css` 가 테마보다 뒤에 로드되므로 모바일에서 덮어쓸 규칙에는 `#wrapper` 를 붙여 우선순위를 높입니다.
- CSS 작성 규칙: 규칙은 한 줄, 클래스명은 언더바(`_`)로 최대 2단어, 속성 순서는 display → position → flex → 크기 → 여백 → 테두리 → 배경 → 글꼴 → 색. Redmine 기본 선택자(`#main-menu` 등)는 예외입니다.

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
