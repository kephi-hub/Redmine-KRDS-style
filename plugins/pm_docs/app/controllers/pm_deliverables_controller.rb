# 프로젝트 > 산출물 — 단계별 목록·KPI, 표준 목록으로 시작, 첨부(버전 이력), 자동 생성 받기, 검수용 일괄 다운로드
class PmDeliverablesController < ApplicationController
  menu_item :deliverables
  helper :pm_docs
  helper :attachments
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_deliverable, only: [:show, :edit, :update, :destroy, :attach, :generate, :review]

  def index
    all = PmDeliverable.where(project_id: @project.id).includes(:owner, :attachments).sorted.to_a
    @kpi = { all: all.size, submitted: all.count(&:done?), review: all.count { |d| d.status == 'review' }, none: all.count { |d| d.status == 'none' },
             late: all.count(&:late?), auto: all.count { |d| d.auto_kind.present? } }
    @phase = params[:phase].presence_in(PmDeliverable::PHASES)
    @status = params[:status].presence_in(PmDeliverable::STATUSES + ['late'])
    list = all
    list = list.select { |d| d.phase == @phase } if @phase
    list = list.select { |d| @status == 'late' ? d.late? : d.status == @status } if @status
    @deliverables = list
  end

  def show
  end

  def new
    @deliverable = PmDeliverable.new(project: @project, phase: params[:phase].presence_in(PmDeliverable::PHASES) || 'analysis')
  end

  def create
    @deliverable = PmDeliverable.new(project: @project)
    @deliverable.assign_attributes(deliverable_params)
    @deliverable.position = (PmDeliverable.where(project_id: @project.id).maximum(:position) || 0) + 1
    @deliverable.save_attachments(params[:attachments])
    if @deliverable.save
      render_attachment_warning_if_needed(@deliverable)
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_pm_deliverable_path(@project, @deliverable)
    else
      render :new
    end
  end

  def edit
  end

  def update
    from = @deliverable.status
    @deliverable.assign_attributes(deliverable_params)
    @deliverable.submitted_on ||= User.current.today if @deliverable.status == 'submitted'
    if @deliverable.save
      @deliverable.log!(User.current, 'edit', from: from, to: @deliverable.status) if from != @deliverable.status
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_deliverable_path(@project, @deliverable)
    else
      render :edit
    end
  end

  def destroy
    @deliverable.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_deliverables_path(@project)
  end

  # 파일 올리기 (새 버전) — 버전 번호를 함께 바꿀 수 있음
  def attach
    @deliverable.version = params[:version].to_s.strip.truncate(20) if params[:version].present?
    @deliverable.status = 'writing' if @deliverable.status == 'none'
    @deliverable.save_attachments(params[:attachments])
    if @deliverable.save && @deliverable.unsaved_attachments.blank?
      names = @deliverable.saved_attachments.map(&:filename).join(', ')
      @deliverable.log!(User.current, 'upload', note: names) if names.present?
      flash[:notice] = l(:notice_pm_attached)
    else
      render_attachment_warning_if_needed(@deliverable)
    end
    redirect_to project_pm_deliverable_path(@project, @deliverable)
  end

  # 검토 흐름: op = request(검토 요청) | approve | reject | submit | reopen, note(의견 — 반려 때는 필수)
  APPROVER_OPS = %w(approve reject reopen).freeze

  def review
    op = params[:op].to_s
    return render_404 unless PmDeliverable::NEXT.key?(op)
    perm = APPROVER_OPS.include?(op) ? :approve_deliverables : :manage_deliverables
    return deny_access unless User.current.allowed_to?(perm, @project)
    unless (PmDeliverable::FLOW[@deliverable.status] || []).include?(op)
      flash[:error] = l(:error_pm_review_state)
      return redirect_to(project_pm_deliverable_path(@project, @deliverable))
    end
    note = params[:note].to_s.strip
    if op == 'reject' && note.empty?
      flash[:error] = l(:error_pm_reject_note)
      return redirect_to(project_pm_deliverable_path(@project, @deliverable))
    end
    from = @deliverable.status
    @deliverable.status = PmDeliverable::NEXT[op]
    @deliverable.submitted_on = User.current.today if op == 'submit'
    PmDeliverable.transaction do
      @deliverable.save!
      @deliverable.log!(User.current, op, from: from, to: @deliverable.status, note: note)
    end
    flash[:notice] = l("notice_pm_review_#{op}")
    redirect_to project_pm_deliverable_path(@project, @deliverable)
  end

  def seed
    n = PmKit::Standard.seed(@project)
    flash[:notice] = l(:notice_pm_seeded, count: n)
    redirect_to project_pm_deliverables_path(@project)
  end

  # 자동 생성 받기: 파일 하나면 그대로, 여러 개면 zip
  def generate
    files = @deliverable.auto_kind.present? ? PmKit::AutoDocs.generate(@deliverable.auto_kind, @project) : []
    if files.empty?
      flash[:error] = l(:error_pm_auto_unavailable)
      return redirect_to(project_pm_deliverable_path(@project, @deliverable))
    end
    if files.size == 1
      name, data = files.first
      return send_file(data[:path], filename: name, type: 'application/zip') if data.is_a?(Hash)
      return send_data(data, filename: name, type: name.end_with?('.txt') ? 'text/plain' : (name.end_with?('.xlsx') ? PmKit::Sheet::XLSX : 'application/octet-stream'))
    end
    buffer = Zip::OutputStream.write_buffer do |zos|
      files.each do |name, data|
        zos.put_next_entry(name)
        data.is_a?(Hash) ? File.open(data[:path], 'rb') { |io| IO.copy_stream(io, zos) } : zos.write(data)
      end
    end
    send_data buffer.string, filename: "#{PmKit::Package.clean(@deliverable.name)}_#{User.current.today.strftime('%Y%m%d')}.zip", type: 'application/zip'
  end

  # 검수용 일괄 다운로드: GET 선택 화면, POST 만들기
  def package
    @all = PmDeliverable.where(project_id: @project.id).includes(:attachments).sorted.to_a
    return unless request.post?
    phases = Array(params[:phases]) & PmDeliverable::PHASES
    list = @all.select { |d| phases.include?(d.phase) }
    list = list.select(&:required) if params[:required_only] == '1'
    path, name, stat = PmKit::Package.build(@project, list, auto: params[:auto] == '1', source: params[:source] == '1')
    Rails.logger.info("[pm_docs] 산출물 패키지 #{@project.identifier} #{User.current.login} #{stat.inspect}")
    send_file path, filename: name, type: 'application/zip', disposition: 'attachment'
  rescue PmKit::Error, SiteTools::RepoExport::Error => e
    flash.now[:error] = e.message
  end

  private

  def find_deliverable
    @deliverable = PmDeliverable.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def deliverable_params
    p = params.require(:pm_deliverable).permit(:phase, :code, :name, :required, :owner_id, :status, :version, :due_on, :submitted_on, :auto_kind, :note)
    p[:owner_id] = nil unless @project.users.exists?(id: p[:owner_id])
    p[:auto_kind] = p[:auto_kind].presence
    p
  end
end
