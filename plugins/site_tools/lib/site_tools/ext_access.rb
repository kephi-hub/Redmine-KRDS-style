# 외부 접속 허용 IP — 외부 프록시(250 nginx, https://www.nanwe.co.kr/pms)를 거쳐 온 요청만 검사
# 사내에서 PMS 서버로 바로 들어오는 접속은 검사하지 않음 (설정을 잘못 넣어도 사내에서 고칠 수 있게)
# 접속자 IP 는 프록시가 넣는 X-Real-IP 만 믿음 (사용자가 보낸 X-Forwarded-For 는 무시)
require 'ipaddr'

module SiteTools
  module ExtAccess
    module_function

    KEYS = %w(ext_ip_enabled ext_ip_private ext_ip_list ext_proxy_list).freeze
    DEFAULTS = { 'ext_ip_enabled' => '0', 'ext_ip_private' => '1', 'ext_ip_list' => '', 'ext_proxy_list' => '192.168.10.250' }.freeze
    PRIVATE = %w(10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.0/8 ::1/128 fc00::/7).map { |c| IPAddr.new(c) }.freeze

    def config
      raw = Setting.plugin_site_tools
      raw = {} unless raw.is_a?(Hash)
      DEFAULTS.merge(raw.stringify_keys.slice(*KEYS))
    end

    # 한 줄에 하나, # 뒤는 메모 → [[IPAddr, 원문], ...], [잘못된 줄]
    def parse(text)
      ok = []
      bad = []
      text.to_s.each_line do |line|
        v = line.sub(/#.*/, '').strip
        next if v.empty?
        ok << [IPAddr.new(v), line.strip]
      rescue IPAddr::Error
        bad << line.strip
      end
      [ok, bad]
    end

    def ip(str)
      IPAddr.new(str.to_s.strip)
    rescue IPAddr::Error
      nil
    end

    # 직접 연결한 상대가 외부 프록시면 프록시가 알려준 접속자 IP, 아니면 nil (사내 직접 접속)
    def external_ip(request, cfg = config)
      peer = ip(request.remote_addr)
      proxies, = parse(cfg['ext_proxy_list'])
      return nil unless peer && proxies.any? { |net, _| net.include?(peer) }
      request.headers['X-Real-IP'].presence || request.headers['X-Forwarded-For'].to_s.split(',').last.to_s.strip
    end

    def private?(addr)
      PRIVATE.any? { |net| net.family == addr.family && net.include?(addr) }
    end

    # [허용 여부, 접속자 IP(외부일 때)]
    def check(request, cfg = config)
      return [true, nil] unless cfg['ext_ip_enabled'] == '1'
      client = external_ip(request, cfg)
      return [true, nil] if client.nil?
      addr = ip(client)
      return [false, client] unless addr
      return [true, client] if cfg['ext_ip_private'] == '1' && private?(addr)
      list, = parse(cfg['ext_ip_list'])
      [list.any? { |net, _| net.family == addr.family && net.include?(addr) }, client]
    end

    # ApplicationController 의 user_setup(설정 캐시를 새로 읽는 곳) 바로 뒤에서 확인 → 로그인 검사보다 먼저, 모든 화면·API 에 적용
    # (그 앞에서 확인하면 설정을 바꾼 직후 첫 요청이 예전 설정을 봄)
    module Guard
      def user_setup
        super
        ok, client = SiteTools::ExtAccess.check(request)
        return if ok
        logger&.warn("[ext_access] 차단 #{client} #{request.request_method} #{request.path}")
        render(template: 'ext_access/denied', formats: [:html], layout: false, status: :forbidden, locals: { client: client })
      end
    end
  end
end
