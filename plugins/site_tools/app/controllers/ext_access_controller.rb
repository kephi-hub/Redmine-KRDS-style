# 관리 > 외부 접속 허용 IP — 외부 프록시(250 nginx)를 거친 접속만 IP 목록으로 제한
class ExtAccessController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :ext_access

  before_action :require_admin

  def index
    @cfg = SiteTools::ExtAccess.config
    @client = SiteTools::ExtAccess.external_ip(request, @cfg)
  end

  def update
    p = params.permit(:ext_ip_enabled, :ext_ip_private, :ext_ip_list, :ext_proxy_list)
    cfg = {
      'ext_ip_enabled' => p[:ext_ip_enabled] == '1' ? '1' : '0',
      'ext_ip_private' => p[:ext_ip_private] == '1' ? '1' : '0',
      'ext_ip_list' => p[:ext_ip_list].to_s.gsub("\r\n", "\n").strip,
      'ext_proxy_list' => p[:ext_proxy_list].to_s.gsub("\r\n", "\n").strip
    }
    _, bad = SiteTools::ExtAccess.parse(cfg['ext_ip_list'])
    _, bad_proxy = SiteTools::ExtAccess.parse(cfg['ext_proxy_list'])
    bad += bad_proxy
    if bad.any?
      flash[:error] = l(:error_ext_ip_invalid, lines: bad.join(', '))
      return redirect_to(ext_access_path)
    end
    # 외부에서 접속 중인 관리자가 자기 IP 를 빼고 켜면 바로 막히므로 저장하지 않음 (사내에서는 언제든 수정 가능)
    ok, client = SiteTools::ExtAccess.check(request, cfg)
    unless ok
      flash[:error] = l(:error_ext_ip_self, ip: client)
      return redirect_to(ext_access_path)
    end
    Setting.plugin_site_tools = merged(cfg)
    flash[:notice] = l(cfg['ext_ip_enabled'] == '1' ? :notice_ext_ip_saved_on : :notice_ext_ip_saved_off)
    redirect_to ext_access_path
  end

  private

  # 같은 설정 칸을 메일 서버(SMTP) 설정과 함께 씀 → 다른 값은 유지
  def merged(cfg)
    raw = Setting.plugin_site_tools
    raw = {} unless raw.is_a?(Hash)
    raw.stringify_keys.merge(cfg)
  end
end
