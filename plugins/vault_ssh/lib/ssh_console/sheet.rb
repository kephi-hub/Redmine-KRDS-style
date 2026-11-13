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
                            widths: [8, 20, 20, 12, 12, 24, 40, 8, 36, 10, 10, 14, 16, 12, 12, 6, 40] },
                          { name: '파일 작업', header: %w(접속\ 번호 시각 사용자 서버 작업 경로 바꾼\ 경로 크기(바이트) 결과),
                            rows: files(list), widths: [10, 20, 12, 24, 12, 50, 50, 14, 30] }])
    end

    def files(list)
      by = list.index_by(&:id)
      SshFileLog.where(ssh_session_id: by.keys).order(:id).map do |g|
        s = by[g.ssh_session_id]
        [g.ssh_session_id, fmt(g.created_at), s.user&.name, s.key_name, I18n.t("label_ssh_fa_#{g.action}"), g.path, g.target, g.size, g.ok ? 'OK' : g.error]
      end
    end
  end
end
