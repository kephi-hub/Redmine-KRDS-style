# SSH 터널 — DB 를 조회하는 동안만 Redmine → SSH 서버(들) → DB 로 포트를 전달하고 바로 닫음
# - 경유 서버 여러 단계 가능 (예: WEB → WAS → DB). 앞 서버를 거쳐 다음 서버의 SSH 포트로 들어감
# - 인증: 비밀번호 또는 개인키(암호 구문 선택). 비밀값은 메모리에서만 사용
# - 서버 지문(SHA256): 저장된 값이 있으면 다르면 거부, 없으면 이번 지문을 알려 줌(저장은 Connector → DbServer#remember_fingerprints)
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

    # 블록에 (로컬 호스트, 로컬 포트, [경유 서버별 지문]) 을 넘김
    def open(server)
      require 'net/ssh'
      require 'timeout'
      hops = server.ssh_route_hops
      sessions = []
      threads = {}
      stops = {}
      verifiers = []
      # 세션마다 따로 멈출 수 있게 (닫을 때 안쪽 세션부터 — 바깥 세션이 안쪽 세션의 통신을 실어 나르므로)
      run = lambda do |ssh|
        stops[ssh] = false
        threads[ssh] = Thread.new do
          ssh.loop(0.05) { !stops[ssh] }
        rescue StandardError
          nil
        end
      end
      begin
        host = nil
        port = nil
        hops.each_with_index do |hop, i|
          if i.zero?
            host = hop[:host]
            port = hop[:port]
          else
            # 앞 서버를 거쳐 이번 서버의 SSH 포트로
            port = sessions.last.forward.local('127.0.0.1', 0, hop[:host], hop[:port])
            host = '127.0.0.1'
            run.call(sessions.last)
          end
          verifier = Verifier.new(hop[:fingerprint])
          verifiers << verifier
          begin
            sessions << Net::SSH.start(host, hop[:username], **ssh_options(server, hop, port, verifier))
          rescue Net::SSH::Exception, SystemCallError, SocketError, Timeout::Error, IOError => e
            raise Error, ssh_message(e, hop, verifier, i, hops.size)
          end
        end
        last = sessions.last
        probe(last, server)
        local = last.forward.local('127.0.0.1', 0, server.host, server.port)
        run.call(last)
        yield '127.0.0.1', local, verifiers.map(&:seen)
      ensure
        sessions.reverse_each do |ssh|
          stops[ssh] = true
          threads[ssh]&.join(3)
          begin
            Timeout.timeout(3) { ssh.close unless ssh.closed? }
          rescue StandardError, Timeout::Error
            begin
              ssh.shutdown!
            rescue StandardError
              nil
            end
          end
        end
      end
    end

    def ssh_options(server, hop, port, verifier)
      opts = { port: port, timeout: server.timeout, non_interactive: true, verify_host_key: verifier,
               config: false, use_agent: false, keepalive: true, logger: Logger.new(nil), keys: [], keys_only: true }
      if hop[:auth] == 'key'
        opts.merge!(auth_methods: %w(publickey), key_data: [hop[:private_key]])
        opts[:passphrase] = hop[:passphrase] if hop[:passphrase].present?
      else
        opts.merge!(auth_methods: %w(password keyboard-interactive), password: hop[:password])
      end
      opts
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
      where = "#{server.ssh_route_hops.last[:host]} → #{server.host}:#{server.port}"
      reason = if result.nil? then 'SSH 서버에서 DB 로 접속 응답이 없음 (DB 주소·포트·방화벽 확인)'
               elsif result[0] == 1 then 'SSH 서버가 포트 전달을 허용하지 않음 (sshd_config AllowTcpForwarding·계정 permitopen 확인)'
               elsif result[0] == 2 then 'SSH 서버에서 DB 에 접속할 수 없음 (DB 주소는 마지막 SSH 서버에서 본 주소로)'
               else result[1].to_s.truncate(150)
               end
      raise Error, "SSH 터널 실패: #{reason} — #{where}"
    end

    def ssh_message(error, hop, verifier, index, total)
      where = "#{hop[:username]}@#{hop[:host]}:#{hop[:port]}"
      where = "#{index + 1}번째 경유 #{where}" if total > 1
      return "SSH 서버 지문이 등록된 값과 다릅니다 (#{where}). 서버를 바꾼 게 맞다면 편집 화면에서 지문을 초기화하세요." if verifier.mismatch
      reason = case error
               when Net::SSH::AuthenticationFailed then '인증 실패 (계정·비밀번호·개인키 확인)'
               when Net::SSH::ConnectionTimeout, Timeout::Error then '응답 없음 (주소·포트·방화벽 확인)'
               when Errno::ECONNREFUSED then '접속 거부 (SSH 포트 확인)'
               when SocketError then '호스트를 찾을 수 없음'
               else error.message.to_s.lines.first.to_s.strip.truncate(200)
               end
      reason = '앞 서버에서 이 서버로 넘어갈 수 없음 (앞 서버의 AllowTcpForwarding·주소 확인)' if index.positive? && error.is_a?(Net::SSH::Disconnect)
      "SSH 터널 실패: #{reason} — #{where}"
    end
  end
end
