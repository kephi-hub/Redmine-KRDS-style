# 화면 캡처 실행 한 번 — 대기 → 실행 중 → 완료 / 실패, 화면 수 · 성공 · 실패 · 바뀐 화면
class MenuCaptureRun < ApplicationRecord
  STATUSES = %w(queued running done failed).freeze

  belongs_to :project
  belongs_to :menu_capture_config, optional: true
  belongs_to :user, optional: true
  has_many :menu_captures, dependent: :nullify

  scope :recent, -> { order(id: :desc) }

  # 실행 중인데 2시간 넘게 끝나지 않으면(서버 재시작 등) 멈춘 것으로
  def self.active_for(project)
    where(project_id: project.id, status: %w(queued running)).where('created_at > ?', 2.hours.ago).recent.first
  end

  def busy?
    %w(queued running).include?(status)
  end
end
