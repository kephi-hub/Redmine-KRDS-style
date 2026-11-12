# 프로젝트 > 투입 인력 — 역할·등급·투입 기간·투입률, 계획·실적 M/M, 보안서약서·계정·회수, 교체 이력, 엑셀
class PmStaffsController < ApplicationController
  menu_item :staff
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_staff, only: [:edit, :update, :destroy]

  def index
    @staffs = PmStaff.where(project_id: @project.id).includes(:user, :replace_of).sorted.to_a
    today = User.current.today
    @from, @to = period
    @month = [today.beginning_of_month, today.end_of_month]
    @months = @staffs.any? ? PmKit::Sheet.staff_months(@staffs, @from, @to) : []
    @kpi = { active: @staffs.count { |s| s.active?(today) }, plan: @staffs.sum { |s| s.plan_mm(@from, @to) }.round(2),
             actual: @staffs.sum { |s| s.actual_mm(@from, @to).to_f }.round(2), month: @staffs.sum { |s| s.plan_mm(*@month) }.round(2),
             nopledge: @staffs.count { |s| s.active?(today) && s.pledge_on.nil? }, unrevoked: @staffs.count { |s| s.end_on && s.end_on < today && s.accounts.present? && s.revoked_on.nil? } }
  end

  def new
    @staff = PmStaff.new(project: @project, role: 'dev', rate: 100, start_on: User.current.today)
    load_form
  end

  def create
    @staff = PmStaff.new(staff_params.merge(project: @project))
    if @staff.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_pm_staffs_path(@project)
    else
      load_form
      render :new
    end
  end

  def edit
    load_form
  end

  def update
    if @staff.update(staff_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_staffs_path(@project)
    else
      load_form
      render :edit
    end
  end

  def destroy
    PmStaff.where(replace_of_id: @staff.id).update_all(replace_of_id: nil)
    @staff.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_staffs_path(@project)
  end

  def export
    from, to = period
    send_data PmKit::Sheet.staff(PmStaff.where(project_id: @project.id).includes(:user, :replace_of).sorted.to_a, from, to),
              filename: "투입인력현황_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  private

  # 사업 기간: 인력 투입 기간 전체 (없으면 올해)
  def period
    list = PmStaff.where(project_id: @project.id)
    from = list.minimum(:start_on) || User.current.today.beginning_of_year
    to = [list.maximum(:end_on), User.current.today].compact.max
    [from, to]
  end

  def find_staff
    @staff = PmStaff.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def load_form
    @members = pm_members(@project)
    @others = PmStaff.where(project_id: @project.id).where.not(id: @staff.id).sorted.to_a
  end

  def staff_params
    p = params.require(:pm_staff).permit(:user_id, :name, :company, :role, :grade, :start_on, :end_on, :rate, :pledge_on, :accounts, :revoked_on,
                                         :replace_of_id, :replace_reason, :replace_approved_on, :note)
    p[:user_id] = nil unless @project.users.exists?(id: p[:user_id])
    p[:replace_of_id] = nil unless PmStaff.exists?(id: p[:replace_of_id], project_id: @project.id)
    p
  end
end
