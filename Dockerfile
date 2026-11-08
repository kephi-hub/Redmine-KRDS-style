# Redmine 6.1.6 + Vault 0.10.5 (Vault 공식 지원 범위: Redmine 5.0~6.1)
FROM redmine:6.1.6

ARG VAULT_COMMIT=185bd854ae73785d7703cda2f88f0c06aaf928bf

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
