# 화면 캡처 — 사이트(또는 프로젝트)별 캡처 설정(로그인 정보 암호화), 실행 기록, 화면별 캡처 이력
class CreateMenuCaptures < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_capture_configs do |t|
      t.references :project, null: false, index: true
      t.integer :menu_site_id
      t.string :base_url, limit: 300
      t.string :login_url, limit: 300
      t.string :username, limit: 100
      t.text :password_enc
      t.string :user_selector, limit: 200
      t.string :pass_selector, limit: 200
      t.string :submit_selector, limit: 200
      t.string :check_selector, limit: 200
      t.integer :width, null: false, default: 1440
      t.boolean :mobile, null: false, default: false
      t.integer :wait_ms, null: false, default: 1000
      t.integer :max_height, null: false, default: 10000
      t.integer :keep, null: false, default: 10
      t.string :schedule, limit: 10, null: false, default: 'off'
      t.boolean :only_active, null: false, default: true
      t.timestamps
    end
    add_index :menu_capture_configs, [:project_id, :menu_site_id], unique: true
    create_table :menu_capture_runs do |t|
      t.references :project, null: false, index: true
      t.integer :menu_capture_config_id, index: true
      t.integer :user_id
      t.string :status, limit: 10, null: false, default: 'queued'
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :total, null: false, default: 0
      t.integer :ok, null: false, default: 0
      t.integer :failed, null: false, default: 0
      t.integer :changed_count, null: false, default: 0
      t.text :error
      t.timestamps
    end
    create_table :menu_captures do |t|
      t.references :project, null: false, index: true
      t.integer :menu_item_id, null: false, index: true
      t.integer :menu_capture_run_id, index: true
      t.string :kind, limit: 10, null: false, default: 'pc'
      t.string :status, limit: 10, null: false, default: 'ok'
      t.string :file, limit: 300
      t.string :thumb, limit: 300
      t.integer :width
      t.integer :height
      t.integer :bytes
      t.string :digest, limit: 40
      t.boolean :changed_from_prev, null: false, default: false
      t.integer :http_status
      t.string :url, limit: 500
      t.string :final_url, limit: 500
      t.string :title, limit: 300
      t.string :error, limit: 500
      t.datetime :captured_at, null: false
    end
    add_index :menu_captures, [:menu_item_id, :kind, :captured_at]
  end
end
