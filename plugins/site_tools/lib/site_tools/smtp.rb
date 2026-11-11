# 메일 서버(SMTP) — 관리 화면에서 입력한 값을 설정 테이블에 저장(비밀번호는 Redmine 암호화 키로 암호화)하고 ActionMailer 에 바로 적용
# config/configuration.yml 의 email_delivery 가 있으면 그쪽이 우선 (이 화면은 읽기 전용 안내)
module SiteTools
  module Smtp
    module_function

    KEYS = %w(enabled address port security authentication user_name password_enc domain verify timeout).freeze
    SECURITY = %w(starttls ssl none).freeze
    AUTH = %w(login plain cram_md5 none).freeze
    DEFAULTS = { 'enabled' => '0', 'port' => '587', 'security' => 'starttls', 'authentication' => 'login', 'verify' => '1', 'timeout' => '15' }.freeze

    def config
      raw = Setting.plugin_site_tools
      raw = {} unless raw.is_a?(Hash)
      DEFAULTS.merge(raw.stringify_keys.slice(*KEYS))
    end

    # configuration.yml 에 메일 설정이 있으면 화면 설정은 쓰지 않음
    def file_configured?
      Redmine::Configuration['email_delivery'].present?
    end

    def password(cfg = config)
      cfg['password_enc'].present? ? Redmine::Ciphering.decrypt_text(cfg['password_enc']) : nil
    end

    # ActionMailer smtp_settings 형식
    def settings_for(cfg, pass = password(cfg))
      s = { address: cfg['address'].to_s.strip, port: cfg['port'].to_i, open_timeout: cfg['timeout'].to_i.clamp(3, 60), read_timeout: cfg['timeout'].to_i.clamp(3, 60) }
      s[:domain] = cfg['domain'].strip if cfg['domain'].present?
      case cfg['security']
      when 'ssl' then s[:tls] = true
      when 'starttls' then s[:enable_starttls] = true
      else s[:enable_starttls_auto] = false
      end
      s[:openssl_verify_mode] = 'none' if cfg['verify'] != '1' && cfg['security'] != 'none'
      if cfg['authentication'] != 'none' && cfg['user_name'].present?
        s.merge!(authentication: cfg['authentication'].to_sym, user_name: cfg['user_name'].strip, password: pass.to_s)
      end
      s
    end

    def usable?(cfg = config)
      cfg['enabled'] == '1' && cfg['address'].present? && cfg['port'].to_i.positive?
    end

    # 지금 프로세스에 적용 (시작할 때·저장할 때). rake·runner 도 시작할 때 적용됨
    def apply!
      return if file_configured?
      cfg = config
      if usable?(cfg)
        ActionMailer::Base.delivery_method = :smtp
        ActionMailer::Base.smtp_settings = settings_for(cfg)
        ActionMailer::Base.perform_deliveries = true
      else
        ActionMailer::Base.perform_deliveries = false
      end
    rescue StandardError => e
      Rails.logger.warn("[site_tools] SMTP 설정 적용 실패: #{e.message}")
    end

    # 시험 메일: 화면에 입력한 값으로 바로 보냄 (저장 전에도). 성공 nil, 실패 메시지
    def test(cfg, pass, to, from)
      require 'mail'
      mail = Mail.new
      mail.from = from.presence || Setting.mail_from
      mail.to = to
      mail.subject = "[#{Setting.app_title}] 메일 서버 시험"
      mail.charset = 'UTF-8'
      mail.body = "#{Setting.app_title} 의 메일 서버(SMTP) 설정 시험 메일입니다.\n보낸 시각: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n"
      mail.delivery_method(:smtp, settings_for(cfg, pass))
      mail.deliver!
      nil
    rescue StandardError, Timeout::Error => e
      e.message.to_s.lines.first.to_s.strip.truncate(300).presence || e.class.name
    end
  end
end
