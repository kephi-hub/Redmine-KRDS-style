# 프로젝트 > 감리 — 감리 회차별 지적사항, 조치 계획·결과·확인, 시정조치 계획서·결과 보고서 엑셀, 가져오기
class PmAuditsController < ApplicationController
  menu_item :audits
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_audit, only: [:show, :edit, :update, :destroy]

  def index
    @rounds = PmAuditRound.where(project_id: @project.id).sorted.to_a
    all = PmAudit.where(project_id: @project.id).includes(:owner, :pm_audit_round).sorted.to_a
    today = User.current.today
    @kpi = { all: all.size, open: all.count { |a| %w(received planned acting).include?(a.status) }, done: all.count { |a| a.status == 'done' },
             verified: all.count { |a| a.status == 'verified' }, late: all.count { |a| a.late?(today) } }
    @round = @rounds.find { |r| r.id.to_s == params[:round].to_s }
    @status = params[:status].presence_in(PmAudit::STATUSES + %w(open late))
    list = all
    list = list.select { |a| a.pm_audit_round_id == @round.id } if @round
    list = case @status
           when 'open' then list.select { |a| %w(received planned acting).include?(a.status) }
           when 'late' then list.select { |a| a.late?(today) }
           when nil then list
           else list.select { |a| a.status == @status }
           end
    @audits = list
    @by_round = all.group_by(&:pm_audit_round_id)
  end

  def show
  end

  def new
    @audit = PmAudit.new(project: @project, pm_audit_round_id: params[:round].presence || PmAuditRound.where(project_id: @project.id).sorted.first&.id, status: 'received')
    load_form
  end

  def create
    @audit = PmAudit.new(audit_params.merge(project: @project, author_id: User.current.id))
    if @audit.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to params[:continue] ? new_project_pm_audit_path(@project, round: @audit.pm_audit_round_id) : project_pm_audit_path(@project, @audit)
    else
      load_form
      render :new
    end
  end

  def edit
    load_form
  end

  def update
    if @audit.update(audit_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_audit_path(@project, @audit)
    else
      load_form
      render :edit
    end
  end

  def destroy
    @audit.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_audits_path(@project)
  end

  def export
    list = PmAudit.where(project_id: @project.id).includes(:owner, :pm_audit_round, :pm_deliverable).sorted.to_a
    send_data PmKit::Sheet.audits(list), filename: "감리시정조치_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  # 감리 보고서의 지적사항 표(엑셀·CSV) 가져오기 → 고른 회차로
  def import
    @rounds = PmAuditRound.where(project_id: @project.id).sorted.to_a
    return unless request.post?
    round = @rounds.find { |r| r.id.to_s == params[:round_id].to_s }
    rows = params[:file].respond_to?(:read) ? PmKit::Importer.read_file(params[:file]) : nil
    return import_error(l(:error_pm_bad_file)) if rows.blank?
    @result = PmKit::Importer.audits(@project, rows, round)
    return import_error(l(:error_pm_no_header)) unless @result
    flash.now[:notice] = l(:notice_pm_imported, created: @result[:created], updated: @result[:updated])
  end

  private

  def find_audit
    @audit = PmAudit.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def load_form
    @rounds = PmAuditRound.where(project_id: @project.id).sorted.to_a
    @members = pm_members(@project)
    @deliverables = @project.module_enabled?(:deliverables) ? PmDeliverable.where(project_id: @project.id).sorted.to_a : []
  end

  def import_error(message)
    flash.now[:error] = message
    render :import
  end

  def audit_params
    p = params.require(:pm_audit).permit(:code, :pm_audit_round_id, :area, :kind, :title, :content, :basis, :plan, :owner_id, :due_on, :result, :status,
                                         :done_on, :verified_on, :issue_id, :pm_deliverable_id)
    p[:owner_id] = nil unless @project.users.exists?(id: p[:owner_id])
    p[:pm_audit_round_id] = nil unless PmAuditRound.exists?(id: p[:pm_audit_round_id], project_id: @project.id)
    p[:pm_deliverable_id] = nil unless PmDeliverable.exists?(id: p[:pm_deliverable_id], project_id: @project.id)
    iid = p[:issue_id].to_s[/\d+/]
    p[:issue_id] = iid && Issue.visible.where(project_id: @project.self_and_descendants.pluck(:id)).exists?(id: iid) ? iid.to_i : nil
    p
  end
end
