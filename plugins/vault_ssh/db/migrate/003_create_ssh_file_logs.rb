# 터미널 파일 창 작업 기록 — 받기·올리기·폴더 만들기·이름 바꾸기·삭제
class CreateSshFileLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :ssh_file_logs do |t|
      t.integer :ssh_session_id, null: false, index: true
      t.string :action, limit: 12, null: false
      t.string :path, limit: 500, null: false
      t.string :target, limit: 500
      t.bigint :size
      t.boolean :ok, null: false, default: true
      t.string :error, limit: 255
      t.datetime :created_at, null: false
    end
  end
end
