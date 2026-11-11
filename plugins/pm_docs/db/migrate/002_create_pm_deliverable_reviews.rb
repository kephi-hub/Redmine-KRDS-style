# 산출물 검토·승인 이력 — 검토 요청·승인·반려·제출·되돌림·수정·파일 올림
class CreatePmDeliverableReviews < ActiveRecord::Migration[7.2]
  def change
    create_table :pm_deliverable_reviews do |t|
      t.references :pm_deliverable, null: false, index: true
      t.integer :user_id
      t.string :action, limit: 12, null: false
      t.string :status_from, limit: 10
      t.string :status_to, limit: 10
      t.string :version, limit: 20
      t.text :note
      t.datetime :created_at, null: false
    end
  end
end
