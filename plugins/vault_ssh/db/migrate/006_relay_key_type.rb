# 경유 서버를 "접속 설정의 체크" 대신 "접속정보 유형"으로 구분 — 유형 '경유 서버' 추가,
# 005 의 relay_only 로 표시했던 접속정보는 그 유형으로 옮기고 칸은 지움
class RelayKeyType < ActiveRecord::Migration[7.2]
  class KeyType < ActiveRecord::Base
    self.table_name = 'vault_key_types'
  end

  class Profile < ActiveRecord::Base
    self.table_name = 'vault_ssh_profiles'
  end

  def up
    if table_exists?(:vault_key_types)
      ssh = KeyType.find_by(name: 'SSH 서버')
      relay = KeyType.find_by(name: '경유 서버') ||
              KeyType.create!(name: '경유 서버', base_type: 'Vault::Password', position: ssh&.position || 2)
      if column_exists?(:vault_ssh_profiles, :relay_only)
        ids = Profile.where(relay_only: true).pluck(:key_id)
        execute "UPDATE #{quote_table_name('keys')} SET vault_type_id = #{relay.id.to_i} WHERE id IN (#{ids.map(&:to_i).join(',')})" if ids.any?
      end
    end
    remove_column :vault_ssh_profiles, :relay_only if column_exists?(:vault_ssh_profiles, :relay_only)
  end

  def down
    add_column :vault_ssh_profiles, :relay_only, :boolean, default: false, null: false unless column_exists?(:vault_ssh_profiles, :relay_only)
  end
end
