# 터미널 채널 — 1회용 접속표(2분 안, 본인, 대기 상태)로 구독 → SSH 세션 시작, 입력·창 크기·끊기
module SshConsole
  class TerminalChannel < ActionCable::Channel::Base
    def subscribed
      s = SshSession.find_by(ticket: params[:ticket].to_s, user_id: current_user.id, status: 'pending')
      return reject unless s && s.created_at > 2.minutes.ago && Runner.get(s.id).nil?
      @sid = s.id
      stream_from "ssh_term_#{s.id}"
      s.update_columns(remote_ip: connection.send(:request).remote_ip.to_s.truncate(60))
      Runner.start(s, params[:cols], params[:rows], ask: Runner.take_ask(s.ticket))
    end

    def input(data)
      Runner.get(@sid)&.push(:i, data['d'].to_s)
    end

    def resize(data)
      Runner.get(@sid)&.push(:r, data['cols'], data['rows'])
    end

    def close(_data = nil)
      Runner.get(@sid)&.stop('user')
    end

    def unsubscribed
      Runner.get(@sid)&.stop('browser') if @sid
    end
  end
end
