# 프로젝트 > 보안 취약점 — 진단 회차(도구 결과 엑셀 가져오기), 항목별 조치·예외, 회차 사이 재진단, 엑셀
class PmSecScansController < ApplicationController
  menu_item :sec_scans
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_scan, only: [:show, :edit, :update, :destroy, :export, :bulk]

  def index
    @scans = PmSecScan.where(project_id: @project.id).sorted.to_a
    counts = PmSecItem.where(pm_sec_scan_id: @scans.map(&:id)).group(:pm_sec_scan_id, :status).count
    @counts = @scans.to_h { |s| [s.id, PmSecItem::STATUSES.to_h { |st| [st, counts[[s.id, st]].to_i] }] }
    @high = PmSecItem.where(pm_sec_scan_id: @scans.map(&:id), level: 'high', status: 'open').group(:pm_sec_scan_id).count
  end

  def show
    items = @scan.pm_sec_items.includes(:fixer, :pm_program).order(Arel.sql("CASE level WHEN 'high' THEN 0 WHEN 'mid' THEN 1 ELSE 2 END"), :file_path, :line).to_a
    @kpi = { all: items.size, open: items.count { |i| i.status == 'open' }, high: items.count { |i| i.level == 'high' && i.status == 'open' },
             fixed: items.count { |i| i.status == 'fixed' }, except: items.count { |i| i.status == 'except' } }
    @status = params[:status].presence_in(PmSecItem::STATUSES)
    @level = params[:level].presence_in(PmSecItem::LEVELS)
    @q = params[:q].to_s.strip
    items = items.select { |i| i.status == @status } if @status
    items = items.select { |i| i.level == @level } if @level
    items = items.select { |i| [i.kind, i.file_path, i.description].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    @items = items
    @kinds = @scan.pm_sec_items.group(:kind).count.sort_by { |_, n| -n }
    @members = pm_members(@project)
  end

  def new
    @scan = PmSecScan.new(project: @project, scanned_on: User.current.today)
  end

  # 회차 만들기 + 결과 파일 가져오기 (파일은 선택)
  def create
    @scan = PmSecScan.new(scan_params.merge(project: @project))
    rows = params[:file].respond_to?(:read) ? PmKit::Importer.read_file(params[:file]) : nil
    if params[:file].respond_to?(:read) && rows.blank?
      flash.now[:error] = l(:error_pm_bad_file)
      return render(:new)
    end
    PmSecScan.transaction do
      @scan.save!
      if rows
        res = PmKit::Importer.sec_items(@project, @scan, rows)
        raise ActiveRecord::Rollback unless res
        flash[:notice] = l(:notice_pm_sec_imported, count: res[:created], carried: res[:carried]) + (res[:errors].any? ? " — #{res[:errors].first(5).map { |l2, m| "#{l2}행 #{m}" }.join(' / ')}" : '')
      else
        flash[:notice] = l(:notice_successful_create)
      end
    end
    if @scan.persisted?
      redirect_to project_pm_sec_scan_path(@project, @scan)
    else
      flash.now[:error] = l(:error_pm_no_header) if rows
      render :new
    end
  rescue ActiveRecord::RecordInvalid
    render :new
  end

  def edit
  end

  def update
    if @scan.update(scan_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_sec_scan_path(@project, @scan)
    else
      render :edit
    end
  end

  def destroy
    @scan.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_sec_scans_path(@project)
  end

  def export
    items = @scan.pm_sec_items.includes(:fixer, :pm_program).order(:kind, :file_path, :line).to_a
    send_data PmKit::Sheet.sec_scan(@scan, items), filename: "보안취약점진단_#{@project.identifier}_#{@scan.scanned_on || User.current.today}.xlsx", type: PmKit::Sheet::XLSX
  end

  # 고른 항목 한꺼번에: 상태(조치 완료·예외·미조치) · 사유 · 조치자
  def bulk
    ids = Array(params[:ids]).map(&:to_i)
    st = params[:status].presence_in(PmSecItem::STATUSES)
    n = 0; errs = []
    @scan.pm_sec_items.where(id: ids).each do |i|
      i.status = st if st
      i.reason = params[:reason] if params[:reason].present?
      i.fixer_id = params[:fixer_id].presence && @project.users.exists?(id: params[:fixer_id]) ? params[:fixer_id].to_i : i.fixer_id
      i.fixed_on = nil if st == 'open'
      i.save ? n += 1 : errs << "#{i.kind}: #{i.errors.full_messages.join(', ')}"
    end
    flash[errs.empty? ? :notice : :error] = l(:notice_pm_sec_bulk, count: n) + (errs.any? ? " — #{errs.first(3).join(' / ')}" : '')
    redirect_to project_pm_sec_scan_path(@project, @scan, status: params[:back_status])
  end

  private

  def find_scan
    @scan = PmSecScan.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def scan_params
    params.require(:pm_sec_scan).permit(:name, :tool, :scanned_on, :revision, :scanner, :note)
  end
end
