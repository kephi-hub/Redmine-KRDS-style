# 인프라 자산 대장 — 공용 자산(project_id 없음, 관리자)과 프로젝트 자산, 공용 자산 ↔ 프로젝트 연결
class CreateOpsAssets < ActiveRecord::Migration[7.2]
  def change
    create_table :ops_assets do |t|
      t.integer :project_id, index: true
      t.string :kind, limit: 12, null: false
      t.string :name, limit: 120, null: false
      t.string :env, limit: 10, null: false, default: 'common'
      t.string :address, limit: 255
      t.text :spec
      t.string :vendor, limit: 120
      t.string :owner, limit: 120
      t.date :expires_on, index: true
      t.string :renew_cycle, limit: 60
      t.integer :db_server_id
      t.integer :jenkins_server_id
      t.text :note
      t.boolean :active, null: false, default: true
      t.integer :author_id
      t.timestamps
    end
    create_table :ops_asset_links do |t|
      t.references :ops_asset, null: false, index: false
      t.references :project, null: false, index: true
    end
    add_index :ops_asset_links, [:ops_asset_id, :project_id], unique: true, name: 'idx_ops_asset_links'
  end
end
