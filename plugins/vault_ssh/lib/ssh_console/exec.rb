# SSH 명령 실행 (다른 기능용) — 접속정보 "SSH 서버" + 접속 설정(경유 포함)으로 연결해 명령 몇 개를 실행하고 바로 닫음
# 스케줄러 crontab 수집 · 자산 서버 정보 수집이 씀. "접속할 때 입력" 서버는 비밀번호가 없어 쓸 수 없음
require 'timeout'

module SshConsole
  module Exec
    module_function

    def open_link(key, user: nil)
      raise TargetError, I18n.t(:error_ssh_not_ssh) unless key && Target.ssh_key?(key)
      profile = VaultSshProfile.find_by(key_id: key.id)
      raise TargetError, I18n.t(:error_ssh_exec_ask) if profile&.auth == 'ask'
      user ||= User.active.where(admin: true).first
      chain = Target.chain(key, profile, user: user)
      link = Connector.open(chain)
      Target.remember(profile, chain, link.fingerprints) if profile
      link
    end

    # 긴 출력(덤프 등)을 받으며 처리 — yield(:out, 데이터) · yield(:err, 데이터) · 끝에 yield(:exit, 종료 코드)
    # stdin: 명령 표준입력으로 보낼 문자열(비밀번호 등) — 보내고 바로 닫음
    def stream(key, cmd, stdin: nil, user: nil)
      link = open_link(key, user: user)
      code = nil
      begin
        ch = link.ssh.open_channel do |c|
          c.exec(cmd) do |c2, ok|
            raise TargetError, I18n.t(:error_ssh_pty) unless ok
            c2.on_data { |_, d| yield(:out, d) }
            c2.on_extended_data { |_, _, d| yield(:err, d) }
            c2.on_request('exit-status') { |_, d| code = d.read_long }
            if stdin
              c2.send_data(stdin)
            end
            c2.eof!
          end
        end
        ch.wait
        link.ssh.loop(0.1) { ch.active? }
      ensure
        link.close
      end
      yield(:exit, code)
      code
    end

    # SFTP 세션으로 작업 후 닫기
    def sftp(key, user: nil)
      require 'net/sftp'
      link = open_link(key, user: user)
      s = Net::SFTP::Session.new(link.ssh).connect!
      begin
        yield s
      ensure
        (s.close_channel rescue nil)
        link.close
      end
    end

    # commands: { 이름 => 명령 } → { 이름 => 출력 } (명령마다 30초)
    def run(key, commands, user: nil, timeout: 30)
      link = open_link(key, user: user)
      begin
        commands.to_h do |name, cmd|
          out = Timeout.timeout(timeout) { link.ssh.exec!(cmd) }
          [name, out.to_s.dup.force_encoding('UTF-8').scrub]
        end
      ensure
        link.close
      end
    end
  end
end
