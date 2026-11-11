# 스케줄(배치) 한 건 — 일정 표현식은 종류에 따라 크론으로 해석(Windows·DB 잡 일부는 글로만)
class OpsSchedule < ApplicationRecord
  KINDS = %w(cron spring quartz windows jenkins db_job other).freeze
  SOURCES = %w(manual crontab db_job jenkins).freeze
  CRON_KINDS = %w(cron spring quartz jenkins db_job).freeze

  belongs_to :project
  belongs_to :ops_asset, optional: true
  has_many :ops_interfaces, dependent: :nullify

  validates :name, presence: true, length: { maximum: 150 }
  validates :kind, inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }
  validates :expression, length: { maximum: 255 }
  validates :run_as, length: { maximum: 60 }
  validates :duration_min, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than: 100_000 }, allow_nil: true
  validate :asset_visible

  before_validation { self.name = name.to_s.strip; self.expression = expression.to_s.strip.presence }

  scope :sorted, -> { order(:name, :id) }

  def asset_visible
    return unless ops_asset_id
    errors.add(:ops_asset_id, :invalid) unless OpsAsset.for_project(project).exists?(id: ops_asset_id)
  end

  # 크론으로 계산할 수 있으면 OpsKit::Cron, 아니면 nil
  def cron
    return nil unless expression.present? && CRON_KINDS.include?(kind)
    @cron ||= OpsKit::Cron.new(expression, quartz: kind == 'quartz')
  end

  def describe
    c = cron
    return expression.presence || '-' unless c
    c.valid? ? c.describe : "#{expression} (#{c.describe})"
  end

  def next_runs(n = 5)
    cron&.next_runs(Time.now, n) || []
  end

  def to_s
    name
  end
end
