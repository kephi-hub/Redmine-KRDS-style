# 터미널 세션 실행 — 접속 기록 1개당 스레드 1개 (net-ssh 이벤트 루프)
# 브라우저 → (ActionCable) → push(:i / :r) → 큐 → 루프 안에서 SSH 채널로
# SSH 채널 출력 → 모아서(30ms) ActionCable 방송 "ssh_term_<id>" (base64) + 녹화
# 제한: 유휴 15분(14분에 경고), 한 세션 4시간 — 끝나면 기록을 닫고 방송 'closed'
module SshConsole
  class Runner
    IDLE = 15 * 60
    WARN = 14 * 60
    MAX = 4 * 60 * 60
    MAX_PER_USER = 5
    MAX_TOTAL = 20

    @all = {}
    @lock = Mutex.new

    class << self
      def get(id)
        @lock.synchronize { @all[id] }
      end

      def count(user_id = nil)
        @lock.synchronize { user_id ? @all.values.count { |r| r.user_id == user_id } : @all.size }
      end

      def register(r)
        @lock.synchronize { @all[r.id] = r }
      end

      def unregister(id)
        @lock.synchronize { @all.delete(id) }
      end

      # 비밀값(접속할 때 입력)은 DB 에 두지 않고 잠깐(2분) 메모리에만
      def stash(ticket, ask)
        @lock.synchronize do
          @asks ||= {}
          @asks.delete_if { |_, v| v[:at] < Time.now - 120 }
          @asks[ticket] = { ask: ask, at: Time.now } if ask
        end
      end

      def take_ask(ticket)
        @lock.synchronize { (@asks ||= {}).delete(ticket)&.dig(:ask) }
      end

      def start(session, cols, rows, ask: nil)
        r = new(session, cols, rows, ask)
        register(r)
        r.run
        r
      end
    end

    attr_reader :id, :user_id

    def initialize(session, cols, rows, ask)
      @id = session.id
      @user_id = session.user_id
      @cols = cols.to_i.clamp(20, 400)
      @rows = rows.to_i.clamp(5, 200)
      @ask = ask
      @queue = Queue.new
      @stop = nil
      @last_input = Time.now
      @warned = false
    end

    def push(kind, *data)
      @last_input = Time.now if kind == :i
      @queue << [kind, *data]
    end

    def stop(reason)
      @stop ||= reason
    end

    def emit(payload)
      ActionCable.server.broadcast("ssh_term_#{@id}", payload)
    end

    def run
      @thread = Thread.new do
        Rails.application.executor.wrap { body }
      end
    end

    private

    def body
      session = SshSession.find(@id)
      key = session.key
      profile = VaultSshProfile.find_by(key_id: key&.id)
      reason = 'error'
      link = nil
      rec = nil
      begin
        raise TargetError, I18n.t(:error_ssh_key_gone) unless key
        chain = Target.chain(key, profile, user: session.user, ask: @ask)
        @ask = nil
        emit(t: 's', s: 'connecting', m: Target.describe(chain))
        link = Connector.open(chain)
        remember_fingerprints(profile, chain, link.fingerprints) if profile
        rec = Recorder.new(session, @cols, @rows) if profile.nil? || profile.record || session.prod?
        session.update_columns(status: 'running', started_at: Time.current, target: Target.describe(chain).truncate(255), record_file: rec&.file)
        # 몇 시간 이어질 수 있으므로 DB 연결은 반납 (끝날 때 다시 빌림)
        ActiveRecord::Base.connection_pool.release_connection
        reason = loop_shell(link.ssh, profile, session, rec)
      rescue StepError, TargetError => e
        session.update_columns(status: 'failed', error: e.message.truncate(500))
        emit(t: 's', s: 'failed', m: e.message)
        reason = 'failed'
      rescue StandardError => e
        Rails.logger.error("[ssh_console] #{@id} #{e.class}: #{e.message}")
        session.update_columns(status: 'failed', error: "#{e.class.name.demodulize}: #{e.message}".truncate(500))
        emit(t: 's', s: 'failed', m: I18n.t(:error_ssh_unknown))
        reason = 'failed'
      ensure
        rec&.close
        link&.close
        if session && session.status == 'running'
          session.update_columns(status: 'closed', ended_at: Time.current, end_reason: reason, bytes_out: @bytes_out.to_i, bytes_in: @bytes_in.to_i)
          emit(t: 's', s: 'closed', r: reason, m: I18n.t("label_ssh_end_#{reason}", default: reason))
        elsif session
          session.update_columns(ended_at: Time.current, end_reason: reason) if session.ended_at.nil?
        end
        self.class.unregister(@id)
      end
    end

    def remember_fingerprints(profile, chain, fps)
      changed = false
      hops = profile.hop_list
      chain.each_with_index do |ep, i|
        fp = fps[i] or next
        if i == chain.size - 1
          (profile.host_key = fp; changed = true) if profile.host_key.blank?
        elsif hops[i] && hops[i]['fp'].blank?
          hops[i]['fp'] = fp
          changed = true
        end
      end
      return unless changed
      profile.hop_list = hops
      profile.save(validate: false)
    end

    def loop_shell(ssh, profile, session, rec)
      out = ''.b
      closed = false
      started = Time.now
      @bytes_out = 0
      @bytes_in = 0
      ch = ssh.open_channel do |c|
        c.request_pty(term: 'xterm-256color', chars_wide: @cols, chars_high: @rows) do |c2, ok|
          raise TargetError, I18n.t(:error_ssh_pty) unless ok
          c2.send_channel_request('shell') do |c3, ok2|
            raise TargetError, I18n.t(:error_ssh_pty) unless ok2
            c3.send_data("#{profile.start_cmd}\n") if profile&.start_cmd.present?
          end
        end
        c.on_data { |_, d| out << d.b }
        c.on_extended_data { |_, _, d| out << d.b }
        c.on_close { closed = true }
        c.on_eof { closed = true }
      end
      emit(t: 's', s: 'connected', m: session.target)
      ssh.loop(0.03) do
        until @queue.empty?
          kind, a, b = @queue.pop(true) rescue break
          case kind
          when :i
            ch.send_data(a.to_s)
            @bytes_in += a.to_s.bytesize
          when :r
            @cols = a.to_i.clamp(20, 400)
            @rows = b.to_i.clamp(5, 200)
            ch.send_channel_request('window-change', :long, @cols, :long, @rows, :long, 0, :long, 0)
            rec&.resize(@cols, @rows)
          end
        end
        unless out.empty?
          rec&.output(out)
          @bytes_out += out.bytesize
          emit(t: 'o', d: Base64.strict_encode64(out))
          out = ''.b
        end
        idle = Time.now - @last_input
        if idle > WARN && !@warned
          @warned = true
          emit(t: 'w', m: I18n.t(:text_ssh_idle_warn))
        end
        @warned = false if idle < WARN
        @stop ||= 'idle' if idle > IDLE
        @stop ||= 'max' if Time.now - started > MAX
        !closed && !@stop
      end
      @stop || 'exit'
    end
  end
end
