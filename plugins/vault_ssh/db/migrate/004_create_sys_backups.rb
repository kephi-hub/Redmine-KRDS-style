# 프로젝트 시스템 백업 — 운영 서버 DB 덤프 · 첨부파일 폴더를 SSH 로 PMS 서버에 날짜별 보관
class CreateSysBackups < ActiveRecord::Migration[7.2]
  def change
    create_table :sys_backup_jobs do |t|
      t.integer :project_id, null: false, index: true
      t.string :name, limit: 100, null: false
      t.integer :vault_key_id, null: false                    # SSH 서버 접속정보 (명령·SFTP 를 실행할 서버)
      t.string :kind, limit: 10, null: false, default: 'db'   # db | files
      t.string :db_kind, limit: 12                            # mysql | postgresql | custom
      t.string :db_host, limit: 255
      t.integer :db_port
      t.string :db_name, limit: 120
      t.integer :db_key_id                                    # 데이터베이스 접속정보 (아이디·비밀번호)
      t.text :dump_cmd                                        # custom: 표준출력으로 덤프를 내보내는 명령
      t.text :paths                                           # files: 한 줄에 하나
      t.text :excludes                                        # files: 제외 패턴, 한 줄에 하나
      t.string :schedule, limit: 10, null: false, default: 'off' # off | daily | weekly
      t.integer :hour, null: false, default: 2
      t.integer :weekday, null: false, default: 7             # 1=월 … 7=일
      t.integer :keep, null: false, default: 14
      t.boolean :active, null: false, default: true
      t.datetime :last_run_at
      t.integer :author_id
      t.timestamps
    end
    create_table :sys_backup_runs do |t|
      t.integer :sys_backup_job_id, null: false, index: true
      t.integer :project_id, null: false, index: true
      t.integer :user_id
      t.string :status, limit: 10, null: false, default: 'queued' # queued | running | done | failed
      t.string :trigger, limit: 10, null: false, default: 'manual' # manual | schedule
      t.string :dir, limit: 255
      t.bigint :bytes, null: false, default: 0                   # 이번에 받은 양
      t.bigint :total_bytes, null: false, default: 0             # 보관본 전체 크기(링크 포함)
      t.integer :files_total, null: false, default: 0
      t.integer :files_new, null: false, default: 0
      t.integer :files_linked, null: false, default: 0
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
  end
end
