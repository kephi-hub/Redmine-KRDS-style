# 개인정보 컬럼 표시 — DB 연결 + 테이블.컬럼마다 분류·암호화 여부 (사람이 확정한 것만 저장)
class CreateDbPrivacyColumns < ActiveRecord::Migration[7.2]
  def change
    create_table :db_privacy_columns do |t|
      t.references :db_link, null: false, index: false
      t.string :table_name, limit: 128, null: false
      t.string :column_name, limit: 128, null: false
      t.string :category, limit: 12, null: false
      t.string :encryption, limit: 10, null: false, default: 'unknown'
      t.string :note, limit: 255
      t.integer :user_id
      t.timestamps
    end
    add_index :db_privacy_columns, [:db_link_id, :table_name, :column_name], unique: true, name: 'idx_db_privacy_cols'
  end
end
