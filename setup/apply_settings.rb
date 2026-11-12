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
  SEED['roles'].each_with_index do |r, i|
    role = if r['builtin'].to_i > 0
             Role.find_by(builtin: r['builtin'])
           else
             # rename_from: 예전 이름의 역할이 있으면 이름만 바꿔 그대로 씀 (구성원 유지)
             Role.find_by(name: r['name'], builtin: 0) || (r['rename_from'] && Role.find_by(name: r['rename_from'], builtin: 0)) || Role.new(builtin: 0)
           end
    role.name = r['name'] if r['builtin'].to_i.zero?
    role.permissions = r['permissions'].map(&:to_sym)
    %w(assignable issues_visibility time_entries_visibility users_visibility).each { |k| role.send("#{k}=", r[k]) if r.key?(k) }
    role.save!; log "#{role.name}: 권한 #{role.permissions.size}개"
  end
  # 역할 목록 순서도 seed 순서대로
  SEED['roles'].reject { |r| r['builtin'].to_i > 0 }.each_with_index do |r, i|
    Role.where(name: r['name'], builtin: 0).update_all(position: i + 1)
  end

  puts '[일감 상태·유형]'
  status = ->(name) { IssueStatus.find_by!(name: name) }
  (SEED['issue_statuses'] || []).each do |s|
    st = IssueStatus.find_or_initialize_by(name: s['name'])
    st.is_closed = s['is_closed'] ? true : false
    st.save!; log "상태 #{st.name}: #{st.is_closed ? '닫힘' : '열림'}"
  end
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

  # 역할의 유형별 권한 — tracker_permissions: { 권한 => [일감 유형 이름] } 이면 그 유형에만 허용 (유형을 만든 뒤에)
  SEED['roles'].select { |r| r['tracker_permissions'] }.each do |r|
    role = Role.find_by(name: r['name'], builtin: 0) or next
    r['tracker_permissions'].each { |perm, names| role.set_permission_trackers(perm, Tracker.where(name: Array(names)).pluck(:id)) }
    role.save!; log "#{role.name}: 유형별 권한 #{r['tracker_permissions'].map { |k, v| "#{k}=#{Array(v).join('/')}" }.join(', ')}"
  end

  puts '[일감 사용자 정의 항목]'
  (SEED['issue_custom_fields'] || []).each do |c|
    cf = IssueCustomField.find_by(name: c['name'])
    trackers = Tracker.where(name: Array(c['trackers'])).to_a
    if cf
      missing = trackers - cf.trackers.to_a
      cf.trackers << missing if missing.any?
      log "#{cf.name}: 있음#{" (일감 유형 #{missing.map(&:name).join(', ')} 연결)" if missing.any?}"
    else
      cf = IssueCustomField.new(name: c['name'], field_format: c['format'], is_for_all: true, is_filter: c['filter'] ? true : false,
                                is_required: c['required'] ? true : false, visible: true, searchable: c['format'] == 'string')
      cf.possible_values = c['values'] if c['values']
      cf.default_value = c['default'] if c['default']
      cf.trackers = trackers
      cf.save!
      log "#{cf.name}: 새로 만듦 (#{trackers.map(&:name).join(', ')})"
    end
  end

  puts '[업무흐름]'
  # 역할 × 일감 유형 조합에 업무흐름이 하나도 없을 때만 기본값을 채움 (관리 화면에서 바꾼 업무흐름은 그대로)
  statuses = IssueStatus.all.index_by(&:name)
  pick = ->(v) { v == 'all' ? statuses.values : Array(v).map { |n| statuses.fetch(n) } }
  (SEED['workflows'] || {}).each do |role_name, rule|
    role = Role.find_by!(name: role_name)
    pairs = pick.(rule['from']).product(pick.(rule['to'])).reject { |a, b| a == b }
    filled = Tracker.all.reject { |t| WorkflowTransition.exists?(role_id: role.id, tracker_id: t.id) }.each do |t|
      WorkflowTransition.insert_all(pairs.map { |a, b| { type: 'WorkflowTransition', role_id: role.id, tracker_id: t.id, old_status_id: a.id, new_status_id: b.id, author: false, assignee: false } })
    end
    log "#{role.name}: #{filled.empty? ? '기존 업무흐름 유지' : "#{filled.map(&:name).join(', ')} 에 기본 흐름 #{pairs.size}개 전환"}"
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
  Setting.new_project_user_role_id = Role.find_by!(name: SEED['new_project_user_role']).id.to_s if SEED['new_project_user_role']
  # 서버마다 다른 값은 .env 에서 받음
  Setting.host_name = ENV['REDMINE_HOST_NAME'] if ENV['REDMINE_HOST_NAME'].present?
  Setting.protocol  = ENV['REDMINE_PROTOCOL'].presence || 'http'
  Setting.sys_api_enabled = '1'
  Setting.sys_api_key = ENV['REDMINE_SYS_API_KEY'] if ENV['REDMINE_SYS_API_KEY'].present?
  Setting.sys_api_key = SecureRandom.hex(20) if Setting.sys_api_key.blank?
  log "설정 #{SEED['settings'].size + 7}개 (테마 #{Setting.ui_theme}, 언어 #{Setting.default_language}, 호스트 #{Setting.host_name})"
end

puts '[완료] 저장소 API 키는 .env 의 REDMINE_SYS_API_KEY 와 cron 설정(setup/cron.example)에 같은 값을 쓰세요.'
