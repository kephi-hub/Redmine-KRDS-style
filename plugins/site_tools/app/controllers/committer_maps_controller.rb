# 저장소 커미터 ↔ 사용자 자동 연결 — 관리 화면(모든 저장소 현황·일괄 갱신)과 저장소 "사용자" 화면의 [자동 연결] 버튼
class CommitterMapsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :committer_maps

  before_action :require_login

  def index
    return deny_access unless User.current.admin?
    @rows = SiteTools::Committers.overview
    @exports = RepoExportLog.recent.includes(:user, :project).limit(30).to_a
  end

  # repository_id 가 있으면 그 저장소만(저장소 관리 권한), 없으면 전체(관리자)
  def refresh
    idx = SiteTools::Committers.user_index
    remap = params[:remap] == '1'
    if params[:repository_id].present?
      repo = Repository.find_by(id: params[:repository_id])
      return render_404 unless repo
      return deny_access unless User.current.allowed_to?(:manage_repository, repo.project)
      r = SiteTools::Committers.refresh(repo, idx, remap: remap)
      flash[:notice] = l(:notice_committers_refreshed, mapped: r[:mapped].size, unmatched: r[:unmatched].size)
      return redirect_to(committers_repository_path(repo))
    end
    return deny_access unless User.current.admin?
    total = Repository.all.to_a.sum { |repo| SiteTools::Committers.refresh(repo, idx, remap: remap)[:mapped].size }
    flash[:notice] = l(:notice_committers_refreshed_all, mapped: total)
    redirect_to committer_maps_path
  end
end
