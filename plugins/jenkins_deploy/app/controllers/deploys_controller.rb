# 프로젝트 > 배포 — 환경별 배포 실행, 진행 상태, 이력
class DeploysController < ApplicationController
  menu_item :deploys
  helper :deploys

  before_action :find_project_by_project_id
  before_action :authorize

  HISTORY_LIMIT = 30

  def index
    @targets = @project.deploy_targets.includes(:jenkins_server).sorted.to_a
    refresh_active_runs
    @filter = @targets.find { |t| t.id == params[:target_id].to_i }
    load_history
  end

  # 진행 중 배포 상태 갱신 (화면에서 10초마다 호출) — 끝난 게 있으면 화면이 새로고침
  def status
    changed = refresh_active_runs
    render json: { changed: changed, active: @project.deploy_runs.active.count }
  end

  def create
    target = @project.deploy_targets.find_by(id: params[:target_id])
    return render_404 unless target
    return deny(l(:error_deploy_not_allowed)) unless target.runnable_by?(User.current)
    return deny(l(:error_deploy_confirm)) if target.production? && params[:confirm].to_s.strip != @project.identifier
    run = target.active_run
    run&.refresh!
    return deny(l(:error_deploy_running)) if run&.reload&.active?

    client = target.jenkins_server.client
    begin
      definitions = client.parameter_definitions(target.job_path)
      values = target.run_params(definitions, params[:jparams] || {})
    rescue ArgumentError => e
      return deny(l(:error_deploy_failed, message: e.message)) # 잘못된 선택지 — 실행하지 않았으므로 기록 없음
    rescue JenkinsDeploy::Error => e
      definitions = nil
      jenkins_error = e
    end

    run = @project.deploy_runs.create!(
      deploy_target: target, user: User.current, target_name: target.name, job_path: target.job_path,
      production: target.production?, note: params[:note].to_s.strip.truncate(255).presence, status: 'queued'
    )
    begin
      raise jenkins_error if jenkins_error
      params_sent = values.merge('REDMINE_USER' => User.current.login, 'REDMINE_RUN_ID' => run.id.to_s)
      run.params = params_sent
      run.queue_id = client.trigger(target.job_path, params_sent, definitions)
      run.save!
      flash[:notice] = l(:notice_deploy_started, name: target.name)
    rescue JenkinsDeploy::Error => e
      run.fail!(e.message)
      flash[:error] = l(:error_deploy_failed, message: e.message)
    end
    redirect_to project_deploys_path(@project)
  end

  private

  def deny(message)
    flash[:error] = message
    redirect_to project_deploys_path(@project)
  end

  def refresh_active_runs
    @project.deploy_runs.active.includes(deploy_target: :jenkins_server).to_a.map(&:refresh!).any?
  end

  # Jenkins 빌드 목록 + Redmine 실행 기록을 빌드 번호로 합침 (Jenkins 에서 직접 실행한 빌드도 표시)
  def load_history
    @errors = {}
    @last = {}
    @definitions = {}
    rows = []
    runs = @project.deploy_runs.includes(:user).order(id: :desc).limit(200).to_a
    # 환경마다 Jenkins 에 한 번 물어 빌드 목록과 매개변수 정의를 함께 가져옴 (확인창 입력칸용)
    @targets.each do |t|
      info = begin
        t.jenkins_server.client.job_info(t.job_path, 20)
      rescue JenkinsDeploy::Error => e
        @errors[t.id] = e.message
        { builds: [], params: nil }
      end
      @definitions[t.id] = info[:params]
      next if @filter && @filter != t
      builds = info[:builds]
      mine = runs.select { |r| r.deploy_target_id == t.id && r.build_number }.index_by(&:build_number)
      builds.each { |b| rows << history_row(t, b, mine[b['number']]) }
    end
    shown = rows.map { |r| r[:run]&.id }.compact
    runs.each do |r|
      next if shown.include?(r.id)
      next if @filter && r.deploy_target_id != @filter.id
      rows << history_row(r.deploy_target, nil, r, r.target_name)
    end
    @history = rows.sort_by { |r| -(r[:time] || Time.zone.at(0)).to_f }.first(HISTORY_LIMIT)
    @targets.each { |t| @last[t.id] = rows.select { |r| r[:target_id] == t.id }.max_by { |r| (r[:time] || Time.zone.at(0)).to_f } }
  end

  def history_row(target, build, run, name = nil)
    if build
      status = build['building'] ? 'running' : DeployRun::RESULTS.fetch(build['result'].to_s, build['result'] ? 'failure' : 'queued')
      time = build['timestamp'] ? Time.zone.at(build['timestamp'].to_i / 1000) : run&.created_at
      duration = build['building'] ? (Time.current - time).to_i : build['duration'].to_i / 1000
      { target_id: target&.id, target_name: target&.name || name, production: target&.production?, number: build['number'],
        url: build['url'], status: status, time: time, duration: duration, run: run,
        by: run&.user || jenkins_cause(build), note: run&.note, params: build_params(build) }
    else
      time = run.started_at || run.created_at
      duration = run.finished_at ? (run.finished_at - time).to_i : (run.active? ? (Time.current - time).to_i : nil)
      { target_id: run.deploy_target_id, target_name: name || run.target_name, production: run.production?, number: run.build_number,
        url: nil, status: run.status, time: time, duration: duration, run: run, by: run.user, note: run.note || run.error_message,
        params: (run.params || {}).except(*DeployTarget::AUTO_PARAMS) }
    end
  end

  def build_params(build)
    Array(build['actions']).flat_map { |a| Array(a && a['parameters']) }
                           .reject { |p| DeployTarget::AUTO_PARAMS.include?(p['name']) }
                           .to_h { |p| [p['name'], p['value'].to_s] }
  end

  def jenkins_cause(build)
    cause = Array(build['actions']).flat_map { |a| Array(a && a['causes']) }.first
    return nil unless cause
    who = cause['userName'].presence || cause['userId'].presence
    who ? "Jenkins · #{who}" : 'Jenkins'
  end
end
