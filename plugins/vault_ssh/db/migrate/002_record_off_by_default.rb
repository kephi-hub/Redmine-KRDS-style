# 화면 녹화 기본값 해제 (운영 서버는 설정과 관계없이 항상 녹화)
class RecordOffByDefault < ActiveRecord::Migration[7.2]
  def change
    change_column_default :vault_ssh_profiles, :record, from: true, to: false
  end
end
