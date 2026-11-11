# SSH 터널 — DB 를 조회하는 동안만 Redmine → SSH 서버(WEB 등) → DB 로 포트를 전달하고 바로 닫음
# - 인증: 비밀번호 또는 개인키(암호 구문 선택). 비밀값은 메모리에서만 사용
# - 서버 지문(SHA256): 저장된 값이 있으면 다르면 거부, 없으면 이번 지문을 알려 줌(저장은 Connector)
module DbManage
  module Tunnel
    # 지문 확인용 (net-ssh verify_host_key 규약)
    class Verifier
      attr_reader :seen, :mismatch

      def initialize(expected)
        @expected = expected.presence
      end

      def verify(arguments)
        @seen = arguments[:key].fingerprint('sha256')
        @seen = "SHA256:#{@seen}" unless @seen.start_with?('SHA256:')
        @mismatch = @expected && @expected != @seen
        !@mismatch
      end

      def verify_signature
        yield
      end
    end

    module_function

    # 블록에 (로컬 호스트, 로컬 포트, 서버 지문) 을 넘김
    def open(server)
      require 'net/ssh'
      verifier = Verifier.new(server.ssh_host_key)
      opts = { port: server.ssh_port, timeout: server.timeout, non_interactive: true, verify_host_key: verifier,
               config: false, use_agent: false, keepalive: true, logger: Logger.new(nil) }
      if server.ssh_auth == 'key'
        opts.merge!(auth_methods: %w(publickey), key_data: [server.ssh_private_key], keys: [], keys_only: true)
        opts[:passphrase] = server.ssh_passphrase if server.ssh_passphrase.present?
      else
        opts.merge!(auth_methods: %w(password keyboard-interactive), password: server.ssh_password, keys: [], keys_only: true)
      end
      begin
        ssh = Net::SSH.start(server.ssh_host, server.ssh_username, **opts)
      rescue Net::SSH::Exception, SystemCallError, SocketError, Timeout::Error, IOError => e
        raise Error, ssh_message(e, server, verifier)
      end
      stop = false
      thread = nil
      begin
        probe(ssh, server)
        port = ssh.forward.local('127.0.0.1', 0, server.host, server.port)
        thread = Thread.new do
          ssh.loop(0.05) { !stop }
        rescue StandardError
          nil
        end
        yield '127.0.0.1', port, verifier.seen
      ensure
        stop = true
        thread&.join(3)
        begin
          ssh.close unless ssh.closed?
        rescue StandardError
          nil
        end
      end
    end

    # 포트 전달을 먼저 한 번 열어 봄 — 거부·DB 접속 실패를 알아보기 쉬운 문구로
    def probe(ssh, server)
      result = nil
      ch = ssh.open_channel('direct-tcpip', :string, server.host, :long, server.port, :string, '127.0.0.1', :long, 0) do |c|
        result = :ok
        c.close
      end
      ch.on_open_failed { |_c, code, desc| result = [code, desc] }
      deadline = Time.now + server.timeout
      ssh.loop(0.05) { result.nil? && Time.now < deadline }
      return if result == :ok
      where = "#{server.ssh_host} → #{server.host}:#{server.port}"
      reason = if result.nil? then 'SSH 서버에서 DB 로 접속 응답이 없음 (DB 주소·포트·방화벽 확인)'
               elsif result[0] == 1 then 'SSH 서버가 포트 전달을 허용하지 않음 (sshd_config AllowTcpForwarding·계정 permitopen 확인)'
               elsif result[0] == 2 then 'SSH 서버에서 DB 에 접속할 수 없음 (DB 주소는 SSH 서버에서 본 주소로)'
               else result[1].to_s.truncate(150)
               end
      raise Error, "SSH 터널 실패: #{reason} — #{where}"
    end

    def ssh_message(error, server, verifier)
      where = "#{server.ssh_username}@#{server.ssh_host}:#{server.ssh_port}"
      return "SSH 서버 지문이 등록된 값과 다릅니다 (#{where}). 서버를 바꾼 게 맞다면 편집 화면에서 지문을 초기화하세요." if verifier.mismatch
      reason = case error
               when Net::SSH::AuthenticationFailed then '인증 실패 (계정·비밀번호·개인키 확인)'
               when Net::SSH::ConnectionTimeout, Timeout::Error then '응답 없음 (주소·포트·방화벽 확인)'
               when Errno::ECONNREFUSED then '접속 거부 (SSH 포트 확인)'
               when SocketError then '호스트를 찾을 수 없음'
               else error.message.to_s.lines.first.to_s.strip.truncate(200)
               end
      "SSH 터널 실패: #{reason} — #{where}"
    end
  end
end
