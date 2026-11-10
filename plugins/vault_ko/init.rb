# Vault 플러그인 한국어화 보조 플러그인 (원본 vault 는 수정하지 않음)
# - config/locales/ko.yml : Vault 번역 키 한국어
# - build.rb + snippets/  : Docker 이미지 빌드 중 Vault 원본 화면을 한국어·개선 화면으로 고침 (Dockerfile 참고)
#   유형 선택칸·유형 표시·유형 관리 카드는 vault_types 플러그인 화면을 불러 씀
#   Vault 원본에는 라이선스 표기가 없어 고친 화면 파일은 저장소에 넣지 않음
Redmine::Plugin.register :vault_ko do
  name 'Vault 한국어'
  author 'kephi-hub'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  description 'Vault 0.10.5 한국어 번역 및 화면 문구'
  version '0.10.5-1'
  requires_redmine_plugin :vault, version_or_higher: '0.10.5'
end
