# 프로젝트 > 스케줄러 — 목록(일정 풀이·다음 실행), 24시간 타임라인(몰림·겹침), 등록·수정(일정 미리보기), 가져오기(crontab·DB 잡·Jenkins), 배치 정의서
class OpsSchedulesController < ApplicationController
  menu_item :ops_schedules
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_schedule, only: [:show, :edit, :update, :destroy]

  def index
    all = OpsSchedule.where(project_id: @project.id).includes(:ops_asset).sorted.to_a
    today = Date.current
    @today_runs = all.select(&:active?).sum { |s| s.cron&.runs_on(today)&.size.to_i }
    @kpi = { all: all.size, active: all.count(&:active?), servers: all.map(&:ops_asset_id).compact.uniq.size,
             unparsed: all.count { |s| s.cron && !s.cron.valid? && s.cron.error != :reboot } }
    @asset_id = params[:asset_id].presence&.to_i
    @kind = params[:kind].presence_in(OpsSchedule::KINDS)
    @q = params[:q].to_s.strip
    list = all
    list = list.select { |s| s.ops_asset_id == @asset_id } if @asset_id
    list = list.select { |s| s.kind == @kind } if @kind
    list = list.select { |s| [s.name, s.command, s.expression, s.owner, s.related].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    list = list.select(&:active?) unless params[:all] == '1'
    @schedules = list
    @assets = all.map(&:ops_asset).compact.uniq.sort_by(&:name)
  end

  # 24시간 타임라인: 시간대별 실행 수, 같은 서버에서 실행 시간이 겹치는 작업
  def timeline
    @date = (Date.parse(params[:date].to_s) rescue Date.current)
    list = OpsSchedule.where(project_id: @project.id, active: true).includes(:ops_asset).sorted.to_a
    @rows = list.map { |s| [s, s.cron&.valid? ? s.cron.runs_on(@date) : nil] }
    @hours = Array.new(24, 0)
    @rows.each { |_, runs| runs&.each { |t| @hours[t.hour] += 1 } }
    @peak = @hours.max.to_i
    @overlaps = overlaps(@rows)
  end

  def show
    @next = @schedule.next_runs(10)
  end

  def new
    @schedule = OpsSchedule.new(project: @project, kind: params[:kind].presence_in(OpsSchedule::KINDS) || 'cron', ops_asset_id: params[:asset_id])
  end

  def create
    @schedule = OpsSchedule.new(schedule_params.merge(project: @project, author_id: User.current.id))
    if @schedule.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_ops_schedule_path(@project, @schedule)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @schedule.update(schedule_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_schedule_path(@project, @schedule)
    else
      render :edit
    end
  end

  def destroy
    @schedule.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_schedules_path(@project)
  end

  # 등록 화면의 일정 미리보기 (확장자 없는 주소 — .json 은 API 요청으로 취급됨)
  def preview
    s = OpsSchedule.new(kind: params[:kind].presence_in(OpsSchedule::KINDS) || 'cron', expression: params[:expression].to_s.strip)
    c = s.cron
    return render(json: { ok: false, text: l(:text_oa_no_cron) }) unless c
    render json: { ok: c.valid?, text: c.describe, next: c.next_runs(Time.now, 5).map { |t| oa_time(t) } }
  end

  # 가져오기: GET 화면(from=db|jenkins 면 그때 접속해 목록), POST from=crontab|db|jenkins
  def import
    @from = params[:from].presence_in(%w(crontab db jenkins ssh))
    if request.get?
      @db_jobs, @db_errors = OpsKit::Importer.db_jobs(@project) if @from == 'db'
      @jk_jobs, @jk_errors = OpsKit::Importer.jenkins_jobs(@project) if @from == 'jenkins'
      @ssh_assets = ssh_assets if @from == 'ssh'
      return
    end
    case @from
    when 'crontab' then import_crontab
    when 'db' then import_db
    when 'jenkins' then import_jenkins
    when 'ssh' then return unless import_ssh
    else return redirect_to(project_ops_schedules_import_path(@project))
    end
    flash[:notice] = l(:notice_oa_imported, created: @result[:created], updated: @result[:updated])
    flash[:warning] = l(:warning_oa_import_skipped, lines: @result[:errors].first(10).join(', ')) if @result[:errors].any?
    flash[:warning] = [flash[:warning], l(:warning_oa_ssh_missing, n: @result[:missing])].compact.join(' / ') if @result[:missing].to_i.positive?
    redirect_to project_ops_schedules_path(@project)
  end

  def export
    send_data OpsKit::Sheet.schedules(OpsSchedule.where(project_id: @project.id).includes(:ops_asset).sorted.to_a),
              filename: "배치정의서_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: OpsKit::Sheet::XLSX
  end

  private

  def find_schedule
    @schedule = OpsSchedule.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def schedule_params
    params.require(:ops_schedule).permit(:name, :kind, :ops_asset_id, :expression, :command, :run_as, :duration_min, :depends_on, :on_failure,
                                         :owner, :related, :active, :note)
  end

  def upsert(key, attrs)
    rec = OpsSchedule.find_by(project_id: @project.id, source_key: key)
    if rec
      rec.assign_attributes(attrs.except(:name, :active))
      rec.changed? && rec.save ? @result[:updated] += 1 : nil
    else
      rec = OpsSchedule.new(attrs.merge(project: @project, source_key: key, author_id: User.current.id))
      rec.save ? @result[:created] += 1 : @result[:errors] << "#{attrs[:name]}: #{rec.errors.full_messages.join(', ')}"
    end
  end

  def import_crontab
    @result = { created: 0, updated: 0, errors: [] }
    asset = OpsAsset.for_project(@project).find_by(id: params[:asset_id])
    items, bad = OpsKit::Importer.parse_crontab(params[:crontab], system: params[:system] == '1')
    @result[:errors] += bad.map { |no, _| "#{no}행" }
    items.each do |it|
      key = OpsKit::Importer.key_for('crontab', asset&.id, it[:expression], it[:command])
      upsert(key, name: it[:name], kind: 'cron', ops_asset_id: asset&.id, expression: it[:expression], command: it[:command], run_as: it[:run_as],
                  source: 'crontab', active: true)
    end
  end

  # 서버에서 가져오기 (SSH) — 서버 자산에 연결한 SSH 접속정보로 crontab 을 읽어 붙여넣기와 같은 방식으로 등록
  def ssh_assets
    return [] unless defined?(SshConsole::Access)
    OpsAsset.for_project(@project).where(kind: 'server', active: true).where.not(vault_key_id: nil).sorted.to_a.select do |a|
      (k = a.vault_key) && SshConsole::Access.can_connect?(User.current, k)
    end
  end

  def import_ssh
    @result = { created: 0, updated: 0, errors: [], missing: 0 }
    asset = ssh_assets.find { |a| a.id == params[:asset_id].to_i }
    unless asset
      flash[:error] = l(:error_oa_no_ssh_key)
      redirect_to(project_ops_schedules_import_path(@project, from: 'ssh'))
      return false
    end
    cmds = {}
    # crontab -l 이 비면(busybox 처럼 setuid 가 아닌 crontab) 계정 crontab 파일을 직접 읽음
    cmds['user'] = 'c=$(crontab -l 2>/dev/null); if [ -n "$c" ]; then printf "%s\\n" "$c"; else cat /var/spool/cron/$(id -un) /var/spool/cron/crontabs/$(id -un) /etc/crontabs/$(id -un) 2>/dev/null; fi' if params[:user_cron] == '1'
    cmds['system'] = 'cat /etc/crontab 2>/dev/null; for f in /etc/cron.d/*; do [ -f "$f" ] && cat "$f"; done 2>/dev/null' if params[:system_cron] == '1'
    if cmds.empty?
      flash[:error] = l(:error_oa_ssh_pick)
      redirect_to(project_ops_schedules_import_path(@project, from: 'ssh'))
      return false
    end
    out = SshConsole::Exec.run(asset.vault_key, cmds, user: User.current)
    keys = []
    out.each do |kind, text|
      items, bad = OpsKit::Importer.parse_crontab(text, system: kind == 'system')
      @result[:errors] += bad.map { |no, _| "#{kind == 'system' ? '시스템' : '계정'} #{no}행" }
      items.each do |it|
        key = OpsKit::Importer.key_for('crontab', asset.id, it[:expression], it[:command])
        keys << key
        upsert(key, name: it[:name], kind: 'cron', ops_asset_id: asset.id, expression: it[:expression], command: it[:command], run_as: it[:run_as],
                    source: 'crontab', active: true)
      end
    end
    # 예전에 이 서버에서 가져왔는데 지금 서버에 없는 작업 — 지우지 않고 알려만 줌
    @result[:missing] = OpsSchedule.where(project_id: @project.id, ops_asset_id: asset.id, source: 'crontab', active: true).where.not(source_key: keys).count
    true
  rescue StandardError => e
    flash[:error] = l(:error_oa_ssh_import, msg: e.message.to_s.truncate(200))
    redirect_to(project_ops_schedules_import_path(@project, from: 'ssh'))
    false
  end

  def import_db
    @result = { created: 0, updated: 0, errors: [] }
    jobs, errors = OpsKit::Importer.db_jobs(@project)
    @result[:errors] += errors
    picked = Array(params[:keys])
    jobs.each do |j|
      key = OpsKit::Importer.key_for('db', j[:link].id, j[:key])
      next unless picked.include?(key)
      upsert(key, name: j[:name], kind: 'db_job', expression: j[:schedule].to_s.truncate(255), command: j[:definition].to_s.truncate(5000),
                  source: 'db_job', active: j[:status].to_s.upcase !~ /DISABLE/, note: "DB: #{j[:link].name}")
    end
  end

  def import_jenkins
    @result = { created: 0, updated: 0, errors: [] }
    jobs, errors = OpsKit::Importer.jenkins_jobs(@project)
    @result[:errors] += errors
    picked = Array(params[:keys])
    jobs.each do |j|
      key = OpsKit::Importer.key_for('jenkins', j[:target].id, j[:label], j[:schedule])
      next unless picked.include?(key)
      upsert(key, name: "#{j[:target].name} (#{j[:label]})", kind: 'jenkins', expression: j[:schedule], command: j[:job], source: 'jenkins', active: true,
                  note: "Jenkins: #{j[:target].jenkins_server&.name}")
    end
  end

  # 같은 서버(자산)에서 실행 구간(시작 ~ 시작+소요 시간)이 겹치는 작업 쌍 — 최대 50개
  def overlaps(rows)
    spans = rows.flat_map do |s, runs|
      next [] unless runs && s.ops_asset_id
      # 소요 시간을 안 적은 작업은 1분으로 봄
      runs.first(300).map { |t| [s, t, t + [s.duration_min.to_i, 1].max.minutes] }
    end
    out = []
    spans.group_by { |s, _, _| s.ops_asset_id }.each_value do |list|
      list.sort_by! { |_, a, _| a }
      list.each_with_index do |(s1, a1, b1), i|
        list[(i + 1)..].each do |s2, a2, b2|
          break if a2 >= b1
          next if s1 == s2
          out << [s1, s2, [a1, a2].max, [b1, b2].min]
          return out.uniq { |x, y, _, _| [x.id, y.id].sort } if out.size >= 50
        end
      end
    end
    out.uniq { |x, y, _, _| [x.id, y.id].sort }
  end
end
