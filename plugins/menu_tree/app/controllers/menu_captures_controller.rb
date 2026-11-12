# 프로젝트 > 메뉴 구조도 > 화면 캡처 — 사이트별 캡처 설정(로그인 정보), [지금 캡처], 화면별 최신 캡처·이력·비교
class MenuCapturesController < ApplicationController
  menu_item :menu_items
  helper :menu_items
  include MenuTree::SiteScope

  before_action :find_project_by_project_id
  before_action :authorize
  before_action -> { load_sites }, except: [:image, :show]

  def index
    @cfg = capture_config
    @run = MenuCaptureRun.where(project_id: @project.id, menu_capture_config_id: @cfg&.id).recent.first if @cfg
    @busy = MenuCaptureRun.active_for(@project)
    ordered = MenuItem.ordered(@project, site: site_filter)
    @index = ordered.to_h { |m, _| [m.id, m] }
    @screens = MenuItem.screens(ordered)
    latest = MenuCapture.where(menu_item_id: @screens.map(&:id), kind: 'pc').order(captured_at: :desc).to_a
    @latest = latest.group_by(&:menu_item_id).transform_values(&:first)
    @filter = params[:filter].presence_in(%w(changed error none nourl a11y))
    list = @screens
    list = case @filter
           when 'changed' then list.select { |m| @latest[m.id]&.changed_from_prev }
           when 'error' then list.select { |m| @latest[m.id] && !@latest[m.id].ok? }
           when 'none' then list.select { |m| m.url.present? && !@latest[m.id] }
           when 'nourl' then list.select { |m| m.url.blank? }
           when 'a11y' then list.select { |m| @latest[m.id]&.a11y_count.to_i.positive? }
           else list
           end
    @list = list
  end

  # 화면 하나의 캡처 이력 · 두 시점 비교
  def show
    @menu = MenuItem.find_by!(id: params[:id], project_id: @project.id)
    @index = MenuItem.where(project_id: @project.id).index_by(&:id)
    @captures = MenuCapture.where(menu_item_id: @menu.id).order(captured_at: :desc).to_a
    pcs = @captures.select { |c| c.kind == 'pc' && c.ok? }
    @a = pcs.find { |c| c.id.to_s == params[:a].to_s } || pcs[0]
    @b = pcs.find { |c| c.id.to_s == params[:b].to_s } || pcs[1]
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 캡처 이미지 (thumb=1 이면 미리보기) · login = 로그인 시험 화면
  def image
    if params[:id] == 'login'
      return deny_access unless User.current.allowed_to?(:manage_menu_captures, @project)
      path = MenuCapture.root.join(@project.id.to_s, 'login_test', "cfg#{params[:cfg].to_i}.png")
      return render_404 unless File.file?(path)
      return send_file(path, type: 'image/png', disposition: 'inline')
    end
    cap = MenuCapture.find_by(id: params[:id], project_id: @project.id)
    path = cap && (params[:thumb] == '1' && cap.thumb_path&.file? ? cap.thumb_path : cap.path)
    return render_404 unless path && File.file?(path)
    send_file path, type: path.to_s.end_with?('.jpg') ? 'image/jpeg' : 'image/png', disposition: params[:download] == '1' ? 'attachment' : 'inline',
                    filename: "#{cap.menu_item.screen_id || cap.menu_item_id}_#{cap.kind}_#{cap.captured_at.strftime('%Y%m%d%H%M')}#{File.extname(path)}"
  end

  # 화면 설계서 (PowerPoint) — 지금 고른 사이트의 화면 (사이트가 없으면 프로젝트 전체)
  def document
    data = MenuTree::ScreenDoc.build(@project, site: @site)
    name = ['화면설계서', @project.identifier, @site&.name, User.current.today.strftime('%Y%m%d')].compact.join('_').gsub(%r{[\\/:*?"<>|\s]+}, '_')
    send_data data, filename: "#{name}.pptx", type: 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
  end

  def settings
    @cfg = capture_config || MenuCaptureConfig.new(project: @project, menu_site: @site, base_url: @site&.url)
  end

  def save_settings
    @cfg = capture_config || MenuCaptureConfig.new(project: @project, menu_site: @site)
    @cfg.assign_attributes(params.require(:menu_capture_config).permit(:base_url, :login_url, :username, :user_selector, :pass_selector, :submit_selector,
                                                                         :check_selector, :logout_url, :width, :mobile, :a11y, :wait_ms, :max_height, :keep, :schedule, :only_active))
    @cfg.password = params[:menu_capture_config][:password] if params[:menu_capture_config][:password].present?
    @cfg.password_enc = nil if params[:clear_password] == '1'
    if @cfg.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_menu_captures_path(@project, site: @site&.id)
    else
      render :settings
    end
  end

  # 로그인 시험 (저장된 설정으로, 몇 초 걸림)
  def test_login
    @cfg = capture_config
    return redirect_to(project_menu_captures_settings_path(@project, site: @site&.id)) unless @cfg&.login?
    @test = MenuTree::Capture.test_login(@cfg)
    render :settings
  end

  def run
    cfg = capture_config
    if !cfg
      flash[:error] = l(:error_menu_capture_no_config)
    elsif !MenuTree::Capture.available?
      flash[:error] = l(:error_menu_capture_no_chrome)
    elsif MenuCaptureRun.active_for(@project)
      flash[:warning] = l(:notice_menu_capture_busy)
    else
      run = MenuCaptureRun.create!(project: @project, menu_capture_config: cfg, user: User.current, status: 'queued')
      MenuTree::CaptureJob.perform_later(run.id)
      flash[:notice] = l(:notice_menu_capture_started)
    end
    redirect_to project_menu_captures_path(@project, site: @site&.id)
  end

  # 웹 접근성 점검표 (엑셀) — 지금 고른 사이트 화면들의 최근 점검 결과
  def a11y
    send_data MenuTree::A11y.sheet(@project, site: @site), filename: "#{['웹접근성_점검', @project.identifier, @site&.name, User.current.today.strftime('%Y%m%d')].compact.join('_').gsub(%r{[\\/:*?"<>|\s]+}, '_')}.xlsx",
                                                       type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 화면 하나의 접근성 위반을 결함 일감으로 (일감 등록 권한도 필요)
  def a11y_issue
    menu = MenuItem.find_by!(id: params[:id], project_id: @project.id)
    cap = MenuCapture.where(menu_item_id: menu.id, kind: 'pc').where.not(a11y_count: nil).order(captured_at: :desc).first
    return render_403 unless User.current.allowed_to?(:add_issues, @project)
    if cap.nil? || cap.a11y_count.to_i.zero?
      flash[:warning] = l(:notice_menu_a11y_nothing)
      return redirect_to(project_menu_capture_path(@project, menu))
    end
    issue = MenuTree::A11y.make_issue(@project, menu, cap, User.current)
    if issue.persisted?
      flash[:notice] = l(:notice_menu_a11y_issue, :id => issue.id)
    else
      flash[:error] = issue.errors.full_messages.join(', ')
    end
    redirect_to project_menu_capture_path(@project, menu)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def capture_config
    MenuCaptureConfig.find_by(project_id: @project.id, menu_site_id: @site&.id)
  end
end
