# Redmine 에서 실행한 배포 기록 (감사용 — 화면에서 수정·삭제 없음)
# 상태는 화면을 볼 때 Jenkins 에 물어 갱신 (백그라운드 작업 없음)
class DeployRun < ApplicationRecord
  belongs_to :project
  belongs_to :deploy_target, optional: true
  belongs_to :user, optional: true

  STATUSES = %w(queued running success failure unstable aborted error).freeze
  ACTIVE = %w(queued running).freeze
  RESULTS = { 'SUCCESS' => 'success', 'FAILURE' => 'failure', 'UNSTABLE' => 'unstable',
              'ABORTED' => 'aborted', 'NOT_BUILT' => 'aborted' }.freeze

  serialize :params, coder: JSON
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE) }

  def active?
    ACTIVE.include?(status)
  end

  # Jenkins 에 대기열·빌드 상태를 물어 갱신. 바뀌었으면 true
  def refresh!
    return false unless active?
    server = deploy_target&.jenkins_server
    return fail!(I18n.t(:error_deploy_target_missing)) unless server

    client = server.client
    if build_number.nil?
      begin
        item = client.queue_item(queue_id)
      rescue JenkinsDeploy::NotFound
        # 대기열 정보는 시작 후 몇 분 뒤 사라짐 → 최근 빌드에서 REDMINE_RUN_ID 로 찾기
        build = client.builds(job_path, 30).find { |b| build_param(b, 'REDMINE_RUN_ID') == id.to_s }
        return fail!(I18n.t(:error_deploy_lost)) unless build
        self.build_number = build['number']
      else
        return finish!('aborted', I18n.t(:error_deploy_cancelled)) if item['cancelled']
        self.build_number = item.dig('executable', 'number')
        return save_if_changed unless build_number
      end
    end
    apply_build(client.build(job_path, build_number))
    save_if_changed
  rescue JenkinsDeploy::Error => e
    Rails.logger.warn "[jenkins_deploy] run #{id}: #{e.message}"
    false
  end

  def apply_build(b)
    self.started_at ||= Time.zone.at(b['timestamp'].to_i / 1000) if b['timestamp']
    if b['building']
      self.status = 'running'
    elsif b['result']
      self.status = RESULTS.fetch(b['result'], 'failure')
      self.finished_at ||= Time.zone.at((b['timestamp'].to_i + b['duration'].to_i) / 1000)
    end
  end

  def build_param(build, name)
    Array(build['actions']).flat_map { |a| Array(a && a['parameters']) }.find { |p| p['name'] == name }&.dig('value').to_s
  end

  def fail!(message)
    finish!('error', message)
  end

  private

  def finish!(state, message)
    self.status = state
    self.error_message = message.to_s.truncate(255)
    self.finished_at ||= Time.current
    save!
    true
  end

  def save_if_changed
    return false unless changed?
    save!
    true
  end
end
