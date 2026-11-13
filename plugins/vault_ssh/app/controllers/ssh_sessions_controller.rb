# 브라우저 터미널 — 접속 만들기(1회용 접속표) · 터미널 탭 · 다시 연결 · 접속 기록 · 녹화 재생 · 엑셀
class SshSessionsController < ApplicationController
  before_action :find_project_by_project_id, except: [:terminal, :again]
  before_action :authorize, except: [:terminal, :again]
  before_action :require_login, only: [:terminal, :again]
  before_action :find_key, only: [:create]
  before_action :find_session, only: [:show, :cast]

  # 접속 정보 확인 → 접속 기록(pending) + 접속표 → 터미널 탭 주소 (JSON)
  def create
    profile = VaultSshProfile.find_by(key_id: @key.id)
    return fail_json(l(:error_ssh_not_allowed), 403) unless SshConsole::Access.can_connect?(User.current, @key, profile)
    reason = params[:reason].to_s.strip.truncate(255, omission: '')
    if profile&.prod?
      return fail_json(l(:error_ssh_reason)) if reason.blank?
      return fail_json(l(:error_ssh_confirm)) unless params[:confirm].to_s.strip == @project.identifier
      return fail_json(l(:error_ssh_twofa)) if SshConsole::PROD_2FA && !User.current.twofa_active?
    end
    ask = nil
    if profile&.auth == 'ask'
      ask = { user: params[:ask_user].to_s.strip, password: params[:ask_password].to_s }
      return fail_json(l(:error_ssh_ask_needed)) if ask[:password].blank?
    end
    return fail_json(l(:error_ssh_limit_user, n: SshConsole::Runner::MAX_PER_USER)) if SshConsole::Runner.count(User.current.id) >= SshConsole::Runner::MAX_PER_USER
    return fail_json(l(:error_ssh_limit_total)) if SshConsole::Runner.count >= SshConsole::Runner::MAX_TOTAL
    s = SshSession.create!(project: @project, key: @key, user: User.current, key_name: @key.name.to_s.truncate(255), env: profile&.env || 'dev',
                           reason: reason.presence, ticket: SecureRandom.urlsafe_base64(32), status: 'pending')
    SshConsole::Runner.stash(s.ticket, ask)
    render json: { ok: true, url: ssh_terminal_path(s.ticket) }
  end

  # 터미널 탭 (전체 화면, Redmine 머리글 없음)
  def terminal
    @session = SshSession.find_by(ticket: params[:ticket].to_s, user_id: User.current.id)
    return render_404 unless @session
    @usable = @session.status == 'pending' && @session.created_at > 2.minutes.ago
    @can_again = @session.key && VaultSshProfile.find_by(key_id: @session.key_id)&.auth != 'ask'
    render layout: false
  end

  # 같은 서버·사유로 새 접속표 (끊긴 뒤 [다시 연결]) — 8시간 안, 접속할 때 입력하는 서버는 제외
  def again
    old = SshSession.find_by(ticket: params[:ticket].to_s, user_id: User.current.id)
    return fail_json(l(:error_ssh_not_allowed), 404) unless old&.key && old.created_at > 8.hours.ago
    profile = VaultSshProfile.find_by(key_id: old.key_id)
    return fail_json(l(:error_ssh_ask_needed)) if profile&.auth == 'ask'
    return fail_json(l(:error_ssh_not_allowed), 403) unless SshConsole::Access.can_connect?(User.current, old.key, profile)
    return fail_json(l(:error_ssh_twofa)) if profile&.prod? && SshConsole::PROD_2FA && !User.current.twofa_active?
    return fail_json(l(:error_ssh_limit_user, n: SshConsole::Runner::MAX_PER_USER)) if SshConsole::Runner.count(User.current.id) >= SshConsole::Runner::MAX_PER_USER
    s = SshSession.create!(project_id: old.project_id, key_id: old.key_id, user: User.current, key_name: old.key.name.to_s.truncate(255),
                           env: profile&.env || 'dev', reason: old.reason, ticket: SecureRandom.urlsafe_base64(32), status: 'pending')
    render json: { ok: true, url: ssh_terminal_path(s.ticket) }
  end

  # 접속 기록 — 모두 보기 권한이 없으면 내 기록만
  def index
    tidy_stale
    scope = list_scope
    @count = scope.count
    @pages = Paginator.new(@count, 50, params[:page])
    @sessions = scope.recent.offset(@pages.offset).limit(@pages.per_page).to_a
  end

  def export
    send_data SshConsole::Sheet.build(list_scope.recent.limit(5000).to_a), filename: "SSH접속기록_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx",
                                                                             type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 녹화 재생
  def show
    @playable = @session.record_path && File.file?(@session.record_path)
  end

  # 녹화 원본 (cast, 압축 풀어서)
  def cast
    path = @session.record_path
    return render_404 unless path && File.file?(path)
    data = Zlib::GzipReader.open(path.to_s, &:read)
    send_data data, type: 'text/plain; charset=utf-8', disposition: params[:download] ? 'attachment' : 'inline',
                    filename: "ssh_#{@session.id}.cast"
  rescue Zlib::Error, EOFError
    send_data(recover(path), type: 'text/plain; charset=utf-8', disposition: 'inline')
  end

  private

  def list_scope
    @all = SshConsole::Access.can_view_all?(User.current, @project)
    scope = SshSession.where(project_id: @project.id).where.not(status: 'pending').includes(:user)
    scope = scope.where(user_id: User.current.id) unless @all
    @env = params[:env].presence_in(VaultSshProfile::ENVS)
    scope = scope.where(env: @env) if @env
    @q = params[:q].to_s.strip
    scope = scope.where('key_name LIKE :q OR reason LIKE :q OR target LIKE :q', q: "%#{@q}%") if @q.present?
    scope
  end

  def fail_json(message, status = 422)
    render json: { ok: false, message: message }, status: status
  end

  def find_key
    @key = Vault::Key.find_by(id: params[:key_id], project_id: @project.id)
    return render_404 unless @key
    render_403 unless SshConsole::Access.key_ok?(User.current, @key)
  end

  def find_session
    @session = SshSession.find_by!(id: params[:id], project_id: @project.id)
    render_403 unless @session.user_id == User.current.id || SshConsole::Access.can_view_all?(User.current, @project)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 서버 재시작 등으로 끊긴 기록 정리
  def tidy_stale
    SshSession.where(project_id: @project.id, status: %w(pending running)).where('created_at < ?', 10.minutes.ago).each do |s|
      next if s.live?
      s.update_columns(status: s.status == 'running' ? 'closed' : 'failed', ended_at: s.ended_at || [s.updated_at, SshConsole::BOOTED_AT].max,
                       end_reason: s.status == 'running' ? 'restart' : 'unused')
    end
  end

  # 비정상 종료로 gzip 끝이 잘린 녹화도 읽을 수 있는 데까지
  def recover(path)
    out = +''
    Zlib::GzipReader.open(path.to_s) do |gz|
      loop { out << gz.readpartial(16_384) }
    rescue Zlib::Error, EOFError
      nil
    end
    out
  rescue StandardError
    out.to_s
  end
end
