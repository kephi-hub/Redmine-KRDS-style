# 프로젝트 > 일정 기준선 — 지금 일감 일정을 기준선으로 저장, 기준선과 지금 일정 비교(지연·앞당김·추가·삭제), 엑셀
class PmBaselinesController < ApplicationController
  menu_item :baselines
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_baseline, only: [:show, :destroy, :export]

  def index
    @baselines = PmBaseline.where(project_id: @project.id).recent.includes(:author).to_a
    return if @baselines.empty?
    @baseline = @baselines.find { |b| b.id.to_s == params[:id].to_s } || @baselines.first
    load_compare
  end

  def show
    @baselines = PmBaseline.where(project_id: @project.id).recent.includes(:author).to_a
    load_compare
    render :index
  end

  def create
    name = params[:name].to_s.strip.presence || "#{User.current.today} 기준선"
    b = PmBaseline.take!(@project, name.truncate(100), User.current, params[:note])
    flash[:notice] = l(:notice_pm_baseline_taken, :name => b.name, :count => b.issue_count)
    redirect_to project_pm_baseline_path(@project, b)
  end

  def destroy
    @baseline.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_baselines_path(@project)
  end

  def export
    send_data PmKit::Sheet.baseline(@baseline, @baseline.compare),
              filename: "일정기준선_비교_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  private

  def load_compare
    @cmp = @baseline.compare
    @filter = params[:filter].presence_in(%w(late early added removed))
    rows = @cmp[:rows]
    @rows = case @filter
            when 'late' then rows.select { |r| r[:due_shift].to_i.positive? }
            when 'early' then rows.select { |r| r[:due_shift].to_i.negative? }
            when 'added', 'removed' then rows.select { |r| r[:kind] == @filter }
            else rows
            end
  end

  def find_baseline
    @baseline = PmBaseline.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
