# SSH 연결 (경유 서버 최대 3대) — DB 관리의 SSH 터널과 별개로 이 플러그인 안에서만 씀
# 단계마다: 앞 단계 세션에 로컬 포트 전달(127.0.0.1:임의 포트 → 다음 서버) → 그 포트로 다음 단계 접속
# 서버 지문(SHA256)은 단계마다 확인: 저장된 값이 있으면 같아야 하고, 없으면 처음 본 값을 돌려줌(저장은 호출한 쪽)
require 'net/ssh'
require 'digest'
require 'base64'

module SshConsole
  class StepError < StandardError
    attr_reader :index, :endpoint, :fingerprint, :kind
    def initialize(msg, index:, endpoint:, fingerprint: nil, kind: :error)
      super(msg)
      @index, @endpoint, @fingerprint, @kind = index, endpoint, fingerprint, kind
    end
  end

  # net-ssh verify_host_key 에 넘기는 확인 객체
  class HostKeyCheck
    attr_reader :seen

    def initialize(expected)
      @expected = expected.presence
    end

    def verify(arguments)
      @seen = 'SHA256:' + Base64.strict_encode64(Digest::SHA256.digest(arguments[:key].to_blob)).delete('=')
      @expected.nil? || @expected == @seen
    end

    def verify_signature
      yield
    end

    def mismatch?
      @expected && @seen && @expected != @seen
    end
  end

  class Link
    attr_reader :ssh, :fingerprints

    def initialize(ssh, gateways, fingerprints)
      @ssh, @gateways, @fingerprints = ssh, gateways, fingerprints
    end

    def close
      begin
        @ssh.close unless @ssh.closed?
      rescue StandardError
        nil
      end
      @gateways.reverse_each do |g|
        g[:stop] = true
        g[:thread]&.join(2)
        begin
          g[:ssh].close unless g[:ssh].closed?
        rescue StandardError
          nil
        end
      end
    end
  end

  module Connector
    module_function

    TIMEOUT = 15

    def options(ep, check, port)
      o = { port: port, timeout: TIMEOUT, non_interactive: true, verify_host_key: check, use_agent: false, config: false,
            user_known_hosts_file: File::NULL, global_known_hosts_file: File::NULL, keepalive: true, keepalive_interval: 30, keepalive_maxcount: 4 }
      if ep.key_data.present?
        o.merge(auth_methods: %w(publickey), key_data: [ep.key_data], keys: [], keys_only: true, passphrase: ep.passphrase.presence)
      else
        o.merge(auth_methods: %w(password keyboard-interactive), password: ep.password.to_s, keys: [], keys_only: true)
      end
    end

    # chain: [Endpoint...] → Link (마지막 단계 세션 + 경유 세션들 + 단계별 지문)
    def open(chain)
      gateways = []
      fps = []
      host, port = chain.first.host, chain.first.port
      chain.each_with_index do |ep, i|
        check = HostKeyCheck.new(ep.fingerprint)
        ssh = begin
          Net::SSH.start(host, ep.user, **options(ep, check, port))
        rescue Net::SSH::HostKeyMismatch, Net::SSH::HostKeyError
          raise StepError.new(I18n.t(:error_ssh_fingerprint, name: ep.label), index: i, endpoint: ep, fingerprint: check.seen, kind: :fingerprint)
        rescue Net::SSH::AuthenticationFailed
          raise StepError.new(I18n.t(:error_ssh_auth, name: ep.label), index: i, endpoint: ep, fingerprint: check.seen, kind: :auth)
        rescue Net::SSH::ConnectionTimeout, Timeout::Error, Errno::ETIMEDOUT
          raise StepError.new(I18n.t(:error_ssh_timeout, name: ep.label), index: i, endpoint: ep, kind: :timeout)
        rescue SocketError, SystemCallError, Net::SSH::Disconnect, Net::SSH::Exception => e
          raise StepError.new(I18n.t(:error_ssh_fingerprint, name: ep.label), index: i, endpoint: ep, fingerprint: check.seen, kind: :fingerprint) if check.mismatch?
          raise StepError.new(I18n.t(:error_ssh_connect, name: ep.label, msg: e.message.to_s.truncate(120)), index: i, endpoint: ep, kind: :connect)
        end
        fps << check.seen
        if i < chain.size - 1
          nxt = chain[i + 1]
          lport = ssh.forward.local(0, nxt.host, nxt.port)
          g = { ssh: ssh, stop: false }
          g[:thread] = Thread.new do
            ssh.loop(0.1) { !g[:stop] }
          rescue StandardError
            nil
          end
          gateways << g
          host, port = '127.0.0.1', lport
        else
          return Link.new(ssh, gateways, fps)
        end
      end
    rescue StandardError
      gateways.each do |g|
        g[:stop] = true
        g[:thread]&.join(1)
        g[:ssh].close rescue nil
      end
      raise
    end

    # 접속 시험 — 열고 바로 닫음. [{ label:, ok:, fp:, message: }]
    def test(chain)
      t0 = Time.now
      link = open(chain)
      steps = chain.each_with_index.map { |ep, i| { label: ep.label, target: ep.to_s, ok: true, fp: link.fingerprints[i] } }
      link.close
      { ok: true, steps: steps, seconds: (Time.now - t0).round(1) }
    rescue StepError => e
      steps = chain.each_with_index.map do |ep, i|
        if i < e.index then { label: ep.label, target: ep.to_s, ok: true }
        elsif i == e.index then { label: ep.label, target: ep.to_s, ok: false, fp: e.fingerprint, message: e.message, kind: e.kind }
        else { label: ep.label, target: ep.to_s, ok: nil }
        end
      end
      { ok: false, steps: steps, message: e.message, kind: e.kind }
    end
  end
end
