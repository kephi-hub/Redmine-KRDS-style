# 접속 기록 엑셀 (감리·보안 점검 자료)
module SshConsole
  module Sheet
    module_function


    def fmt(t)
      t&.in_time_zone(ActiveSupport::TimeZone['Asia/Seoul'])&.strftime('%Y-%m-%d %H:%M:%S')
    end

    def build(list)
      rows = list.map do |s|
        [s.id, fmt(s.started_at || s.created_at), fmt(s.ended_at), s.user&.name, s.user&.login, s.key_name, s.target,
         I18n.t("label_ssh_env_#{s.env}"), s.reason, s.duration && (s.duration / 60.0).round(1),
         I18n.t("label_ssh_status_#{s.status}"), s.end_reason && I18n.t("label_ssh_end_#{s.end_reason}", default: s.end_reason),
         s.remote_ip, s.bytes_in, s.bytes_out, s.record_file.present? ? 'O' : '', s.error]
      end
      KrdsUi::Xlsx.build([{ name: 'SSH 접속 기록', rows: rows,
                            header: %w(번호 시작 종료 사용자 아이디 서버 접속\ 경로 구분 사유 시간(분) 상태 종료\ 사유 접속\ IP 입력(바이트) 출력(바이트) 녹화 오류),
                            widths: [8, 20, 20, 12, 12, 24, 40, 8, 36, 10, 10, 14, 16, 12, 12, 6, 40] }])
    end
  end
end
