# 월간 운영 보고서 — 정기점검·장애·일감 처리·배포 이력(jenkins_deploy)·DB 구조 변경(db_manage)·만료 예정 자산
module OpsKit
  module Report
    module_function

    def range(month)
      z = OpsKit::Cron.zone
      from = z.local(month.year, month.month, 1)
      [from, from.next_month]
    end

    def build(project, month)
      from, to = range(month)
      r = { project: project, month: month, from: from, to: to }
      r[:incidents] = OpsIncident.where(project_id: project.id, occurred_at: from...to).includes(:ops_asset, :issue).order(:occurred_at).to_a
      r[:checks] = OpsCheck.where(project_id: project.id, checked_on: from.to_date...to.to_date).includes(:user).order(:checked_on).to_a
      issues = Issue.where(project_id: project.id)
      created = issues.where(created_on: from...to).group(:tracker_id).count
      closed = issues.where(closed_on: from...to).group(:tracker_id).count
      trackers = Tracker.where(id: created.keys | closed.keys).sorted.to_a
      r[:issue_rows] = trackers.map { |t| [t.name, created[t.id].to_i, closed[t.id].to_i] }
      r[:issue_open] = issues.open.where('created_on < ?', to).count
      r[:deploys] = if defined?(DeployRun) && project.module_enabled?(:jenkins_deploy)
                      DeployRun.where(project_id: project.id, created_at: from...to).includes(:user).order(:created_at).to_a
                    else [] end
      r[:snapshots] = if defined?(DbSnapshot) && project.module_enabled?(:db_manage)
                        DbSnapshot.joins(:db_link).where(db_links: { project_id: project.id }, created_at: from...to).includes(:db_link, :user).order(:created_at).to_a
                      else [] end
      r[:expiring] = OpsAsset.for_project(project).where(active: true).where.not(expires_on: nil).where('expires_on < ?', (to + 1.month).to_date).order(:expires_on).to_a
      r[:downtime] = r[:incidents].sum { |i| i.downtime_min.to_i }
      r
    end

    def fmt(t)
      t && t.in_time_zone(OpsKit::Cron.zone).strftime('%Y-%m-%d %H:%M')
    end

    def xlsx(r)
      lab = OpsKit::Sheet::LABEL
      summary = [
        ['프로젝트', r[:project].name], ['기간', "#{r[:month].strftime('%Y-%m')} (#{r[:from].to_date} ~ #{(r[:to] - 1.day).to_date})"],
        ['장애', "#{r[:incidents].size}건 · 중단 #{r[:downtime]}분"], ['정기점검', "#{r[:checks].size}회 · 이상 항목 #{r[:checks].sum(&:issue_count)}건"],
        ['일감 등록', r[:issue_rows].sum { |x| x[1] }], ['일감 완료', r[:issue_rows].sum { |x| x[2] }], ['월말 미완료 일감', r[:issue_open]],
        ['배포', "#{r[:deploys].size}회 (성공 #{r[:deploys].count { |d| d.status == 'success' }})"],
        ['DB 구조 저장본', "#{r[:snapshots].size}건 (변경 #{r[:snapshots].count(&:changed?)})"], ['만료 예정 자산(다음 달까지)', r[:expiring].size]
      ]
      inc = r[:incidents].map do |i|
        ["#{i.grade}등급", i.title, fmt(i.occurred_at), fmt(i.detected_at), fmt(i.recovered_at), i.downtime_min, i.ops_asset&.name || i.target,
         i.impact, i.cause, i.action, i.prevention, i.issue_id ? "##{i.issue_id}" : nil, lab['status'][i.status]]
      end
      chk = r[:checks].flat_map do |c|
        c.result_list.map { |x| [c.checked_on.to_s, c.name, c.user&.name, x['item'], lab['check'][x['result']], x['action']] }
      end
      dep = r[:deploys].map { |d| [fmt(d.created_at), d.target_name, d.production ? '운영' : '개발', d.build_number, d.status, d.user&.name, d.note] }
      snaps = r[:snapshots].map do |s|
        h = s.summary_hash
        [fmt(s.created_at), s.db_link.name, s.table_count, h ? "추가 #{h[:only_b]} · 삭제 #{h[:only_a]} · 변경 #{h[:changed]} · 객체 #{h[:objects]}" : '첫 저장본', s.user&.name]
      end
      exp = r[:expiring].map { |a| [lab['kind'][a.kind], a.name, a.address, a.expires_on.to_s, a.days_left, a.owner] }
      KrdsUi::Xlsx.build([
        { name: '요약', header: %w(항목 내용), rows: summary, widths: [26, 60] },
        { name: '장애', header: %w(등급 제목 발생 인지 복구 중단(분) 대상 영향 원인 조치 재발방지 일감 상태), rows: inc,
          widths: [8, 30, 17, 17, 17, 9, 20, 30, 30, 30, 30, 8, 8] },
        { name: '정기점검', header: %w(점검일 점검 점검자 항목 결과 조치), rows: chk, widths: [12, 24, 10, 40, 8, 40] },
        { name: '일감 처리', header: %w(유형 등록 완료), rows: r[:issue_rows], widths: [16, 8, 8] },
        { name: '배포 이력', header: %w(일시 대상 구분 빌드 결과 실행자 메모), rows: dep, widths: [17, 24, 6, 8, 10, 10, 30] },
        { name: 'DB 구조 변경', header: %w(저장 일시 DB 테이블\ 수 변경 저장자), rows: snaps, widths: [17, 16, 10, 40, 10] },
        { name: '만료 예정 자산', header: %w(종류 이름 주소 만료일 남은\ 일 담당), rows: exp, widths: [10, 26, 30, 12, 8, 12] }
      ])
    end
  end
end
