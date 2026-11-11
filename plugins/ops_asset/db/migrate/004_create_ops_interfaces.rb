# 연계 인터페이스 — 상대 시스템·방향·방식·주기(스케줄 연결)·데이터·주소·담당
class CreateOpsInterfaces < ActiveRecord::Migration[7.2]
  def change
    create_table :ops_interfaces do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 30, null: false
      t.string :name, limit: 150, null: false
      t.string :direction, limit: 6, null: false, default: 'send'
      t.string :partner, limit: 120, null: false
      t.string :protocol, limit: 10, null: false, default: 'rest'
      t.string :cycle, limit: 10, null: false, default: 'realtime'
      t.integer :ops_schedule_id
      t.text :data_desc
      t.text :tables
      t.string :dev_url, limit: 255
      t.string :prod_url, limit: 255
      t.string :our_owner, limit: 120
      t.string :partner_owner, limit: 120
      t.string :partner_contact, limit: 255
      t.string :auth_note, limit: 255
      t.string :status, limit: 10, null: false, default: 'active'
      t.text :note
      t.integer :author_id
      t.timestamps
    end
    add_index :ops_interfaces, [:project_id, :code], unique: true
  end
end
