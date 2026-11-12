# PMS 백업 상태 — 서버의 setup/backup.sh 가 backup/ctl 에 쓰는 status.json · list.json 을 읽고,
# 화면 [지금 백업] 은 ctl/request 를 만들어 두면 서버 cron(1분마다)이 백업을 시작함
# (컨테이너에는 backup/ctl 만 마운트 — compose.yaml)
require 'json'

module SiteTools
  module Backup
    module_function

    def dir
      Pathname.new(ENV['PMS_BACKUP_CTL'].presence || Rails.root.join('backup_ctl').to_s)
    end

    def mounted?
      dir.directory?
    end

    def read_json(name, default)
      f = dir.join(name)
      f.file? ? JSON.parse(f.read) : default
    rescue JSON::ParserError
      default
    end

    def status
      read_json('status.json', nil)
    end

    def list
      read_json('list.json', [])
    end

    def running_since
      f = dir.join('running')
      f.file? ? f.read.strip : nil
    end

    def requested?
      dir.join('request').file?
    end

    def writable?
      mounted? && File.writable?(dir.to_s)
    end

    def request!(user)
      dir.join('request').write(user.login.to_s)
    end

    # 마지막 성공 시각 (목록의 가장 최근 이름 기준)
    def last_ok_at
      name = list.first&.dig('name')
      return nil unless name
      Time.zone.strptime(name, '%Y-%m-%d_%H%M') rescue nil
    end

    # 26시간 넘게 성공한 백업이 없으면 경고 (매일 03:00 기준 여유)
    def stale?
      t = last_ok_at
      t.nil? || t < 26.hours.ago
    end
  end
end
