# 접속정보(Vault) 유형 관리 — 관리자가 유형 목록(이름·입력 방식·순서)을 정함
# - Vault 원본은 고치지 않음. 유형은 vault_key_types 테이블, 접속정보에는 keys.vault_type_id 만 추가
# - 입력 방식은 Vault 기본 3가지(비밀번호·SFTP·키 파일) 중 하나 → 저장 구조·암호화는 Vault 그대로
# - Vault 화면 연결(유형 선택칸·유형 표시·관리 카드)은 vault_ko/build.rb 가 이미지 빌드 때 넣음
require_relative 'lib/vault_types/keys_controller_patch'

Redmine::Plugin.register :vault_types do
  name '접속정보 유형'
  author 'kephi-hub'
  description '접속정보(Vault) 유형 목록 관리'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'
  requires_redmine_plugin :vault, version_or_higher: '0.10.5'
end

# Redmine 6 은 init.rb 를 준비 단계 이후에 읽으므로 바로 적용
Vault::Key.belongs_to :vault_type, class_name: 'VaultKeyType', optional: true unless Vault::Key.reflect_on_association(:vault_type)
KeysController.prepend(VaultTypes::KeysControllerPatch) unless KeysController.ancestors.include?(VaultTypes::KeysControllerPatch)
KeysController.helper(VaultTypesHelper)
VaultSettingsController.helper(VaultTypesHelper)
