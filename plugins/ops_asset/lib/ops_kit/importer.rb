# 스케줄 가져오기 — crontab 붙여넣기, DB 잡(db_manage 가 읽은 이벤트·pg_cron·스케줄러·에이전트 작업), Jenkins 주기 빌드
# 가져온 항목은 source_key 로 같은 것을 알아봄(다시 가져오면 갱신, 중복 안 생김)
require 'digest'

module OpsKit
  module Importer
    module_function

    ENV_LINE = /\A[A-Za-z_][A-Za-z0-9_]*\s*=/

    # crontab 문자열 → [{ expression:, command:, run_as:, name:, line: }], 해석 못 한 줄은 errors
    # system: /etc/crontab 형식(시각 5칸 다음에 실행 계정)
    def parse_crontab(text, system: false)
      items = []
      errors = []
      text.to_s.each_line.with_index(1) do |raw, no|
        line = raw.strip
        next if line.empty? || line.start_with?('#') || line.match?(ENV_LINE)
        tokens = line.split(/\s+/)
        if tokens.first.start_with?('@')
          expr = tokens.shift
        else
          if tokens.size < 6
            errors << [no, line]
            next
          end
          expr = tokens.shift(5).join(' ')
        end
        user = system && tokens.size > 1 ? tokens.shift : nil
        cmd = tokens.join(' ')
        cron = OpsKit::Cron.new(expr)
        if cmd.empty? || !(cron.valid? || cron.error == :reboot)
          errors << [no, line]
          next
        end
        items << { expression: expr, command: cmd, run_as: user, name: guess_name(cmd), line: no }
      end
      [items, errors]
    end

    # 명령에서 이름 짐작: 스크립트 파일 이름 (없으면 앞 40자)
    def guess_name(cmd)
      c = cmd.sub(/\s*[12]?>>?.*\z/, '').strip
      script = c.split(/\s+/).find { |t| t.match?(/\.(sh|py|rb|pl|php|jar|js|bat|cmd|ps1)\z/i) || t.include?('/') }
      base = script ? File.basename(script) : c
      base.to_s.truncate(40).presence || 'cron'
    end

    def key_for(*parts)
      Digest::SHA1.hexdigest(parts.map(&:to_s).join("\u0001"))[0, 40]
    end

    # DB 잡: [{ link:, key:, name:, schedule:, status:, definition: }] , 실패한 연결은 errors
    def db_jobs(project)
      return [[], []] unless defined?(DbLink) && project.module_enabled?(:db_manage)
      out = []
      errors = []
      DbLink.where(project_id: project.id).includes(:db_server).each do |link|
        snap = link.connector.snapshot(objects: true)
        (snap.dig(:objects, 'event') || []).each do |o|
          out << { link: link, key: o[:key], name: o[:name], schedule: o[:schedule], status: o[:status], definition: o[:definition] }
        end
      rescue StandardError => e
        errors << "#{link.name}: #{e.message.to_s.truncate(150)}"
      end
      [out, errors]
    end

    # Jenkins 주기 빌드: 배포 대상 작업의 config.xml 에서 TimerTrigger(빌드 주기)·SCMTrigger(SCM 폴링) spec
    def jenkins_jobs(project)
      return [[], []] unless defined?(DeployTarget) && project.module_enabled?(:jenkins_deploy)
      out = []
      errors = []
      DeployTarget.where(project_id: project.id).includes(:jenkins_server).each do |t|
        client = t.jenkins_server.client
        res = client.send(:request, :get, client.job_url(t.job_path) + '/config.xml')
        xml = Nokogiri::XML(res.body.to_s)
        { 'hudson.triggers.TimerTrigger' => '빌드 주기', 'hudson.triggers.SCMTrigger' => 'SCM 폴링' }.each do |tag, label|
          xml.xpath("//#{tag}/spec").each do |spec|
            spec.text.to_s.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }.each do |line|
              out << { target: t, job: t.job_path, label: label, schedule: line }
            end
          end
        end
      rescue StandardError => e
        errors << "#{t.name}: #{e.message.to_s.truncate(150)}"
      end
      [out, errors]
    end
  end
end
