# DB 이관 실행 기록 — plan: [{ table, mode }], results: [{ table, mode, status, plan, ddl, rows, target_rows, backup, warnings, error, seconds }]
class DbMigration < ApplicationRecord
  belongs_to :project
  belongs_to :user, optional: true
  belongs_to :source_link, class_name: 'DbLink', optional: true
  belongs_to :target_link, class_name: 'DbLink', optional: true

  STATUSES = %w(queued running done partial failed).freeze
  scope :recent, -> { order(id: :desc) }

  def plan_list
    JSON.parse(plan.presence || '[]')
  rescue JSON::ParserError
    []
  end

  def result_list
    v = results
    v = JSON.parse(v) if v.is_a?(String)
    v.is_a?(Array) ? v : []
  rescue JSON::ParserError
    []
  end

  def results=(value)
    super(value.is_a?(String) ? value : value.to_json)
  end

  # 서버가 다시 시작돼 끊긴 실행은 6시간 뒤 멈춘 것으로
  def busy?
    %w(queued running).include?(status) && created_at > 6.hours.ago
  end

  def backup_dir
    DbManage::Migrator.backup_root.join(project_id.to_s, id.to_s)
  end

  def seconds
    started_at && finished_at ? (finished_at - started_at).round : nil
  end
end
