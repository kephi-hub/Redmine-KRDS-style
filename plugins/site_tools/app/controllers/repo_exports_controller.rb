# 저장소 > [소스코드 다운로드] — 지금 폴더·리비전을 zip 으로 (svn export / git archive), 기록 남김
class RepoExportsController < ApplicationController
  before_action :find_repository

  def show
    return deny_access unless User.current.allowed_to?(:export_repository, @project)
    path = params[:path].to_s
    zip, name, files, bytes = SiteTools::RepoExport.build(@repository, path, params[:rev])
    log('ok', path, files: files, bytes: bytes)
    send_file zip, filename: name, type: 'application/zip', disposition: 'attachment'
  rescue SiteTools::RepoExport::Error => e
    log('error', path, message: e.message)
    flash[:error] = e.message
    # 잠시 뒤 다시(바쁨·시간·크기)면 보던 폴더로, 경로·리비전 오류면 저장소 첫 화면으로
    keep = [:error_repo_export_busy, :error_repo_export_timeout, :error_repo_export_large].any? { |k| e.message == l(k) }
    redirect_to({ controller: 'repositories', action: 'show', id: @project, repository_id: @repository.identifier_param,
                  path: (keep ? path.presence : nil), rev: (keep ? params[:rev].presence : nil) })
  end

  private

  def find_repository
    @project = Project.find(params[:project_id])
    @repository = @project.repositories.find_by(identifier: params[:repository_id]) || @project.repositories.find_by(id: params[:repository_id]) ||
                  (params[:repository_id].blank? ? @project.repository : nil)
    return render_404 unless @repository
    return deny_access unless @project.module_enabled?(:repository)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def log(status, path, files: nil, bytes: nil, message: nil)
    RepoExportLog.create!(user_id: User.current.id, repository_id: @repository.id, project_id: @project.id, path: path.to_s.truncate(500),
                          rev: params[:rev].to_s.truncate(60).presence || 'HEAD', files: files, bytes: bytes, status: status,
                          message: message.to_s.truncate(255).presence, created_at: Time.now)
  rescue StandardError => e
    Rails.logger.warn("[site_tools] 다운로드 기록 실패: #{e.message}")
  end
end
