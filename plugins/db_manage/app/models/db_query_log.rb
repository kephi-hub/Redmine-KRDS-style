# SQL 조회 실행 기록 — status: ok · error · blocked
class DbQueryLog < ApplicationRecord
  belongs_to :db_link
  belongs_to :user, optional: true
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
