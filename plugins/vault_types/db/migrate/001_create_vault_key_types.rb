class CreateVaultKeyTypes < ActiveRecord::Migration[7.2]
  class Row < ActiveRecord::Base
    self.table_name = 'vault_key_types'
  end

  DEFAULTS = [
    ['비밀번호', 'Vault::Password'], ['SSH 서버', 'Vault::Password'], ['데이터베이스', 'Vault::Password'],
    ['웹 관리자', 'Vault::Password'], ['API 키', 'Vault::Password'], ['SFTP', 'Vault::Sftp'],
    ['인증서·키 파일', 'Vault::KeyFile']
  ].freeze

  def up
    create_table :vault_key_types do |t|
      t.string :name, limit: 60, null: false
      t.string :base_type, limit: 40, null: false, default: 'Vault::Password'
      t.integer :position, null: false, default: 1
      t.timestamps
    end
    add_index :vault_key_types, :name, unique: true
    add_column :keys, :vault_type_id, :integer
    add_index :keys, :vault_type_id

    DEFAULTS.each_with_index { |(name, base), i| Row.create!(name: name, base_type: base, position: i + 1) }
    # 기존 접속정보는 같은 입력 방식의 첫 유형(비밀번호 / SFTP / 인증서·키 파일)으로 연결
    Row.order(:position).group_by(&:base_type).each do |base, rows|
      execute "UPDATE #{quote_table_name('keys')} SET vault_type_id = #{rows.first.id.to_i} WHERE vault_type_id IS NULL AND type = #{quote(base)}"
    end
  end

  def down
    remove_index :keys, :vault_type_id
    remove_column :keys, :vault_type_id
    drop_table :vault_key_types
  end
end
