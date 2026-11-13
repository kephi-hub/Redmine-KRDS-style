# 접속정보 등록·수정 때 고른 유형을 저장: 유형의 입력 방식으로 Vault type 을 정하고, 저장 뒤 vault_type_id 기록
module VaultTypes
  module KeysControllerPatch
    def create
      apply_vault_type
      super
      store_vault_type
    end

    def update
      apply_vault_type
      super
      store_vault_type
    end

    # 프로젝트 접속정보 목록 기본 순서 = 드래그로 정한 순서(번호 없는 것은 뒤에 이름순). 제목 칸을 눌러 정렬하면 그 순서
    def sort_clause
      return super unless action_name == 'index' && @project && params[:sort].blank?
      t = Vault::Key.table_name
      [Arel.sql("#{t}.position IS NULL"), Arel.sql("#{t}.position"), Arel.sql("#{t}.name")]
    end

    private

    def apply_vault_type
      @vault_type = VaultKeyType.find_by(id: params.dig(:vault_key, :vault_type_id))
      params[:vault_key][:type] = @vault_type.base_type if @vault_type
    end

    def store_vault_type
      return unless @vault_type && @key&.persisted? && @key.errors.empty?
      @key.update_column(:vault_type_id, @vault_type.id) if @key.vault_type_id != @vault_type.id
    end
  end
end
