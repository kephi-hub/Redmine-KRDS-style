# 프로젝트 > 준공 체크리스트 — 자동 항목(요구사항·시험·결함·산출물·감리·보안·인력) + 직접 확인 항목, 완료보고 엑셀
class PmClosingController < ApplicationController
  menu_item :closing
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize

  def index
    @items = PmKit::Closing.items(@project)
    @progress = PmKit::Closing.progress(@items)
  end

  # 직접 확인 항목 체크·메모
  def check
    key = params[:key].to_s
    return render_404 unless PmKit::Closing::MANUAL_KEYS.include?(key)
    c = PmClosingCheck.find_or_initialize_by(project_id: @project.id, key: key)
    c.done = params[:done] == '1'
    c.note = params[:note].to_s.strip.truncate(1000).presence
    c.user = User.current
    c.checked_at = Time.current
    c.save!
    flash[:notice] = l(:notice_successful_update)
    redirect_to project_pm_closing_path(@project, anchor: "cl_#{key}")
  end

  def export
    send_data PmKit::Closing.sheet(@project),
              filename: "준공체크리스트_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end
end
