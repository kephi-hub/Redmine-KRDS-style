module VaultTypesHelper
  # 접속정보 유형 이름 (관리자가 정한 유형, 없으면 Vault 기본 유형 이름)
  def vault_type_label(key)
    key.vault_type&.name.presence || t("activerecord.models.#{key.type.to_s.underscore.split('/').last}")
  end

  # 유형 선택칸에서 처음 선택할 유형: 저장된 유형 > 같은 입력 방식의 첫 유형
  def vault_type_current(key, types)
    types.find { |t| t.id == key.vault_type_id } || types.find { |t| t.base_type == key.type } || types.first
  end

end
