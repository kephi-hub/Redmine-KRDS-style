# Redmine 기준 설정 적용 — setup/seed.yml, setup/welcome.md 를 읽어 DB 에 반영
# 실행: docker compose exec redmine sh -c 'bundle exec rails runner setup/apply_settings.rb'
# 여러 번 실행해도 결과가 같음 (이미 있으면 갱신, 없으면 생성). 프로젝트·일감 등 데이터는 건드리지 않음.
require 'yaml'

DIR  = File.expand_path(__dir__)
SEED = YAML.safe_load(File.read(File.join(DIR, 'seed.yml')))
def log(msg) = puts("  - #{msg}")

abort '기본 데이터가 없습니다. 먼저 rake redmine:load_default_data REDMINE_LANG=ko 를 실행하세요.' if IssueStatus.none?

ActiveRecord::Base.transaction do
  puts '[역할]'
  (SEED['remove_roles'] || []).each do |name|
    role = Role.find_by(name: name, builtin: 0) or next
    if role.members.any?
      log "#{name}: 구성원이 있어 삭제하지 않음"
    else
      role.destroy!; log "#{name}: 삭제"
    end
  end
  SEED['roles'].each do |r|
    role = r['builtin'].to_i > 0 ? Role.find_by(builtin: r['builtin']) : Role.find_or_initialize_by(name: r['name'], builtin: 0)
    role.permissions = r['permissions'].map(&:to_sym)
    role.save!; log "#{role.name}: 권한 #{role.permissions.size}개"
  end

  puts '[일감 상태·유형]'
  status = ->(name) { IssueStatus.find_by!(name: name) }
  base = Tracker.order(:position).first
  SEED['trackers'].each do |t|
    tracker = Tracker.find_or_initialize_by(name: t['name'])
    created = tracker.new_record?
    tracker.default_status = status.(t['default_status'])
    tracker.save!
    if created && base # 새 유형은 첫 유형의 업무흐름을 복사
      tracker.copy_workflow_rules(base)
    end
    log "#{tracker.name}#{' (새로 만듦, 업무흐름 복사)' if created}"
  end

  puts '[작업분류·문서 범주]'
  { TimeEntryActivity => SEED['time_entry_activities'], DocumentCategory => SEED['document_categories'] }.each do |klass, names|
    names.each_with_index do |name, i|
      e = klass.find_or_initialize_by(name: name, project_id: nil)
      e.active = true; e.position = i + 1; e.save!
    end
    log "#{klass.name}: #{names.join(', ')}"
  end

  puts '[설정]'
  SEED['settings'].each { |k, v| Setting.send("#{k}=", v) }
  # 시간대를 지정하지 않은 계정은 기본 시간대로 맞춤 (컨테이너가 UTC 라 비어 있으면 9시간 늦게 표시됨). 직접 고른 시간대는 유지
  UserPreference.where(time_zone: [nil, '']).update_all(time_zone: Setting.default_users_time_zone) if Setting.default_users_time_zone.present?
  Setting.welcome_text = File.read(File.join(DIR, 'welcome.md'))
  Setting.commit_update_keywords = SEED['commit_update_keywords'].map do |k|
    { 'keywords' => k['keywords'], 'status_id' => status.(k['status']).id.to_s, 'done_ratio' => k['done_ratio'].to_s, 'if_tracker_id' => '' }
  end
  Setting.commit_logtime_activity_id = TimeEntryActivity.find_by!(name: SEED['commit_logtime_activity'], project_id: nil).id.to_s
  Setting.default_projects_tracker_ids = Tracker.where(name: SEED['default_projects_trackers']).order(:id).pluck(:id).map(&:to_s)
  # 서버마다 다른 값은 .env 에서 받음
  Setting.host_name = ENV['REDMINE_HOST_NAME'] if ENV['REDMINE_HOST_NAME'].present?
  Setting.protocol  = ENV['REDMINE_PROTOCOL'].presence || 'http'
  Setting.sys_api_enabled = '1'
  Setting.sys_api_key = ENV['REDMINE_SYS_API_KEY'] if ENV['REDMINE_SYS_API_KEY'].present?
  Setting.sys_api_key = SecureRandom.hex(20) if Setting.sys_api_key.blank?
  log "설정 #{SEED['settings'].size + 7}개 (테마 #{Setting.ui_theme}, 언어 #{Setting.default_language}, 호스트 #{Setting.host_name})"
end

puts '[완료] 저장소 API 키는 .env 의 REDMINE_SYS_API_KEY 와 cron 설정(setup/cron.example)에 같은 값을 쓰세요.'
