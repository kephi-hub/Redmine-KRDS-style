# 보안약점 진단 항목 — 유형·위험도·파일·라인, 미조치 → 조치 완료 / 예외(오탐·위험 수용, 사유 필수), 재진단 결과
# item_key(유형+파일+라인)로 회차 사이를 이어 봄
require 'digest'

class PmSecItem < ApplicationRecord
  LEVELS = %w(high mid low).freeze
  STATUSES = %w(open fixed except).freeze
  RECHECKS = %w(pass fail).freeze

  belongs_to :project
  belongs_to :pm_sec_scan
  belongs_to :fixer, class_name: 'User', optional: true
  belongs_to :pm_program, optional: true

  validates :kind, presence: true, length: { maximum: 150 }
  validates :level, inclusion: { in: LEVELS }
  validates :status, inclusion: { in: STATUSES }
  validates :recheck, inclusion: { in: RECHECKS }, allow_blank: true
  validates :file_path, length: { maximum: 500 }
  validates :reason, presence: true, if: -> { status == 'except' }

  before_validation do
    self.file_path = file_path.to_s.strip.presence
    self.item_key = self.class.key_for(kind, file_path, line)
    self.fixed_on ||= User.current.today if status == 'fixed'
  end

  def self.key_for(kind, path, line)
    Digest::SHA1.hexdigest([kind.to_s.strip.downcase, path.to_s.strip.sub(%r{\A[./\\]+}, '').downcase, line.to_i].join('|'))
  end

  def location
    [file_path, (line ? ":#{line}" : nil)].compact.join
  end
end
