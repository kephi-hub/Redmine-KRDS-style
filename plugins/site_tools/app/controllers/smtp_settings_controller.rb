# 관리 > 메일 서버(SMTP) — 주소·포트·보안·인증·계정·비밀번호(암호화 저장)·발신 주소, 저장 전 시험 메일
class SmtpSettingsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :smtp_settings

  before_action :require_admin

  def index
    @cfg = SiteTools::Smtp.config
    @has_password = @cfg['password_enc'].present?
  end

  def update
    return redirect_to(smtp_settings_path) if SiteTools::Smtp.file_configured?
    cfg, error = form_config
    if error
      flash[:error] = error
      return redirect_to(smtp_settings_path)
    end
    Setting.plugin_site_tools = cfg
    Setting.mail_from = params[:mail_from].to_s.strip if params[:mail_from].present?
    SiteTools::Smtp.apply!
    flash[:notice] = l(cfg['enabled'] == '1' ? :notice_smtp_saved_on : :notice_smtp_saved_off)
    redirect_to smtp_settings_path
  end

  # 화면에 입력한 값으로 시험 메일 (비밀번호를 비워 두면 저장된 값)
  def test
    cfg, error = form_config
    return render(json: { ok: false, message: error }) if error
    to = params[:test_to].to_s.strip.presence || User.current.mail
    return render(json: { ok: false, message: l(:error_smtp_no_to) }) unless to.to_s.match?(/\A[^@\s]+@[^@\s]+\z/)
    pass = params[:password].presence || SiteTools::Smtp.password
    message = SiteTools::Smtp.test(cfg, pass, to, params[:mail_from].to_s.strip)
    render json: message ? { ok: false, message: l(:error_smtp_test, message: message) } : { ok: true, message: l(:notice_smtp_test_ok, to: to) }
  end

  private

  def form_config
    old = SiteTools::Smtp.config
    p = params.permit(:enabled, :address, :port, :security, :authentication, :user_name, :password, :domain, :verify, :timeout, :clear_password)
    cfg = {
      'enabled' => p[:enabled] == '1' ? '1' : '0',
      'address' => p[:address].to_s.strip,
      'port' => p[:port].to_s.strip,
      'security' => p[:security].presence_in(SiteTools::Smtp::SECURITY) || 'starttls',
      'authentication' => p[:authentication].presence_in(SiteTools::Smtp::AUTH) || 'login',
      'user_name' => p[:user_name].to_s.strip,
      'domain' => p[:domain].to_s.strip,
      'verify' => p[:verify] == '1' ? '1' : '0',
      'timeout' => p[:timeout].to_i.clamp(3, 60).to_s,
      'password_enc' => p[:clear_password] == '1' ? nil : old['password_enc']
    }
    cfg['password_enc'] = Redmine::Ciphering.encrypt_text(p[:password]) if p[:password].present?
    return [cfg, l(:error_smtp_address)] if cfg['enabled'] == '1' && cfg['address'] !~ /\A[A-Za-z0-9._\-]+\z/
    return [cfg, l(:error_smtp_port)] unless (1..65_535).cover?(cfg['port'].to_i)
    [cfg, nil]
  end
end
