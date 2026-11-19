# 관리 > SSH 접속 기록 — 모든 프로젝트의 SSH 접속·녹화를 한 곳에서 (관리자 전용)
# 녹화 재생·파일 기록은 프로젝트 접속 기록 화면(ssh_sessions#show)으로 연결 — 관리자는 그대로 열림
class AdminSshSessionsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :admin_ssh_sessions

  before_action :require_admin

  def index
    scope = list_scope
    @count = scope.count
    @pages = Paginator.new(@count, 50, params[:page])
    @sessions = scope.order(id: :desc).offset(@pages.offset).limit(@pages.per_page).to_a
    @projects = Project.where(id: SshSession.distinct.select(:project_id)).sorted.to_a
    @recorded_total = scope.where.not(record_file: [nil, '']).count # 지금 거른 조건 안에서
  end

  def export
    send_data SshConsole::Sheet.build(list_scope.order(id: :desc).limit(5000).to_a),
              filename: "SSH접속기록_전체_#{User.current.today.strftime('%Y%m%d')}.xlsx",
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  private

  def list_scope
    scope = SshSession.where.not(status: 'pending').includes(:user, :project, :ssh_file_logs)
    @project_id = params[:project_id].to_i
    scope = scope.where(project_id: @project_id) if @project_id.positive?
    @env = params[:env].presence_in(VaultSshProfile::ENVS)
    scope = scope.where(env: @env) if @env
    @recorded = params[:recorded] == '1'
    scope = scope.where.not(record_file: [nil, '']) if @recorded
    @q = params[:q].to_s.strip
    if @q.present?
      users = User.like(@q).pluck(:id)
      scope = scope.where('key_name LIKE :q OR reason LIKE :q OR target LIKE :q OR remote_ip LIKE :q', q: "%#{@q}%").or(scope.where(user_id: users))
    end
    scope
  end
end
