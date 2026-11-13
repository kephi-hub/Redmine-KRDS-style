# ActionCable 연결 — Redmine 로그인 세션으로 사용자 확인
# 같은 출처(Origin 호스트 = 요청 호스트)만 허용. 채널은 SshConsole::TerminalChannel (1회용 접속표로 구독)
module SshConsole
  module Cable
    class Connection < ActionCable::Connection::Base
      identified_by :current_user

      def connect
        self.current_user = find_user || reject_unauthorized_connection
      end

      private

      def find_user
        origin = request.headers['Origin'].to_s
        if origin.present?
          host = (URI.parse(origin).host rescue nil)
          return nil unless host && host == request.host
        end
        uid = request.session[:user_id]
        return nil unless uid && User.verify_session_token(uid, request.session[:tk])
        User.active.find_by(id: uid)
      end
    end
  end
end
