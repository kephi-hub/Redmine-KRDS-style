# Redmine 6.1.6 + Vault 0.10.5 (Vault 공식 지원 범위: Redmine 5.0~6.1)
FROM redmine:6.1.6

ARG VAULT_COMMIT=185bd854ae73785d7703cda2f88f0c06aaf928bf

# Oracle Instant Client (DB 관리 플러그인의 Oracle 접속용, Oracle Free Use Terms) — 버전 고정
# Debian 13 은 libaio 가 libaio1t64(libaio.so.1t64) 라 Instant Client 가 찾는 libaio.so.1 링크를 만들어 둠
ARG ORACLE_IC_DIR=2370000
ARG ORACLE_IC_VER=23.7.0.25.01
ENV ORACLE_HOME=/opt/oracle/instantclient \
    LD_LIBRARY_PATH=/opt/oracle/instantclient \
    NLS_LANG=AMERICAN_AMERICA.AL32UTF8
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends libaio1t64 unzip; \
    mkdir -p /opt/oracle; cd /opt/oracle; \
    for p in basiclite sdk; do \
      wget -q -O ic.zip "https://download.oracle.com/otn_software/linux/instantclient/${ORACLE_IC_DIR}/instantclient-${p}-linux.x64-${ORACLE_IC_VER}.zip"; \
      unzip -q -o ic.zip; rm ic.zip; \
    done; \
    mv instantclient_* instantclient; \
    ln -sf /usr/lib/x86_64-linux-gnu/libaio.so.1t64 /usr/lib/x86_64-linux-gnu/libaio.so.1; \
    apt-get purge -y --auto-remove unzip; \
    rm -rf /var/lib/apt/lists/*

# DB 관리 플러그인의 gem(SSH 터널용 net-ssh 등)도 같은 단계에서 설치 — 실행 때는 같은 Gemfile 이 plugins/db_manage 로 마운트됨
COPY plugins/db_manage/Gemfile plugins/db_manage/Gemfile

# Vault 의존 gem(iconv 등)은 네이티브 빌드가 필요 → 빌드 도구 잠깐 설치 후 제거
# 공식 이미지와 동일하게 임시 database.yml 로 Gemfile.lock 의 DB 어댑터 구성을 유지
RUN set -eux; \
    savedAptMark="$(apt-mark showmanual)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends gcc make libc6-dev git; \
    git clone https://github.com/noshutdown-ru/vault plugins/vault; \
    git -C plugins/vault checkout "$VAULT_COMMIT"; \
    rm -rf plugins/vault/.git; \
    for adapter in mysql2 postgresql sqlserver sqlite3; do \
      printf '%s:\n  adapter: %s\n' "$adapter" "$adapter" >> config/database.yml; \
    done; \
    bundle install --jobs "$(nproc)"; \
    rm config/database.yml; \
    chmod -R ugo=rwX Gemfile.lock "$GEM_HOME"; \
    apt-mark auto '.*' > /dev/null; \
    [ -z "$savedAptMark" ] || apt-mark manual $savedAptMark > /dev/null; \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
    rm -rf /var/lib/apt/lists/*; \
    mkdir -p keys; chown -R redmine:redmine plugins keys

# Vault 화면 한국어화·개선: 원본 화면을 이미지 안에서 고침 (원본에서 문구를 못 찾으면 빌드 실패)
COPY plugins/vault_ko/build.rb /tmp/vault_ko/build.rb
COPY plugins/vault_ko/snippets /tmp/vault_ko/snippets
RUN ruby /tmp/vault_ko/build.rb plugins/vault && rm -rf /tmp/vault_ko && chown -R redmine:redmine plugins/vault
