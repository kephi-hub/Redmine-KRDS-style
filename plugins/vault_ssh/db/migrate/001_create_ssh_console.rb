# 브라우저 SSH 터미널 — 접속정보(Vault) "SSH 서버" 의 SSH 설정(1:1) · 접속 기록
class CreateSshConsole < ActiveRecord::Migration[7.2]
  def change
    create_table :vault_ssh_profiles do |t|
      t.integer :key_id, null: false
      t.integer :port
      t.string :auth, limit: 10, null: false, default: 'password' # password | key | ask
      t.integer :key_file_id
      t.text :key_pass_enc
      t.text :hops                                                 # JSON [{key_id:, fp:} | {host:, port:, user:, secret_enc:, fp:}]
      t.string :host_key, limit: 120
      t.string :start_cmd, limit: 255
      t.string :env, limit: 10, null: false, default: 'dev'        # dev | prod
      t.boolean :record, null: false, default: true
      t.timestamps
    end
    add_index :vault_ssh_profiles, :key_id, unique: true
    create_table :ssh_sessions do |t|
      t.integer :project_id, null: false, index: true
      t.integer :key_id, index: true
      t.integer :user_id, null: false, index: true
      t.string :key_name, limit: 255
      t.string :target, limit: 255
      t.string :env, limit: 10, null: false, default: 'dev'
      t.string :reason, limit: 255
      t.string :ticket, limit: 64, null: false
      t.string :status, limit: 12, null: false, default: 'pending' # pending | running | closed | failed
      t.string :end_reason, limit: 30
      t.string :remote_ip, limit: 60
      t.datetime :started_at
      t.datetime :ended_at
      t.bigint :bytes_out, null: false, default: 0
      t.bigint :bytes_in, null: false, default: 0
      t.string :record_file, limit: 255
      t.text :error
      t.timestamps
    end
    add_index :ssh_sessions, :ticket, unique: true
  end
end
