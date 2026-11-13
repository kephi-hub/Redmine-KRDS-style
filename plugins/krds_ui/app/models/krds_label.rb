# 바꾼 메뉴·모듈 이름 한 줄 (KrdsUi::Labels 가 읽음)
class KrdsLabel < ApplicationRecord
  KINDS = %w(top group project module).freeze

  validates :kind, inclusion: { in: KINDS }
  validates :key, presence: true, length: { maximum: 60 }
  validates :name, presence: true, length: { maximum: 60 }
end
