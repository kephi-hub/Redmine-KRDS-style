module DeploysHelper
  # 상태 배지 (성공·실패·진행 중 등)
  # 대기·진행 중이면 스피너를 붙임
  def deploy_status_tag(status)
    spin = DeployRun::ACTIVE.include?(status.to_s) ? content_tag(:span, '', class: 'dep_spin', 'aria-hidden' => 'true') : ''.html_safe
    content_tag(:span, spin + l("label_deploy_status_#{status}"), class: "dep_st st_#{status}")
  end

  # 진행 중 소요 칸: 경과 시간 / 예상 시간 + 진행바 (화면에서 1초마다 갱신). 예상 시간이 없으면 왕복 진행바
  def deploy_progress(row)
    start = row[:time]&.to_i
    est = row[:estimate].to_i
    pct = est > 0 ? [(row[:duration].to_i * 100 / est), 99].min : nil
    text = content_tag(:span, content_tag(:span, deploy_duration(row[:duration]), class: 'dep_elapsed') +
           (est > 0 ? content_tag(:span, " / 약 #{deploy_duration(est)}", class: 'dep_est') : ''.html_safe), class: 'dep_time')
    bar = content_tag(:span, content_tag(:i, '', style: ("width:#{pct}%" if pct)),
                      class: "dep_prog#{' wait' unless pct}", role: 'progressbar',
                      'aria-valuemin' => 0, 'aria-valuemax' => 100, 'aria-valuenow' => pct,
                      'aria-label' => l(:label_deploy_status_running))
    content_tag(:span, text + bar, class: 'dep_live', data: { start: start, est: (est if est > 0) })
  end

  # 초 → "2분 05초"
  def deploy_duration(seconds)
    return '-' if seconds.nil?
    s = seconds.to_i
    s < 60 ? "#{s}초" : format('%d분 %02d초', s / 60, s % 60)
  end

  # 변경 내역 칸: 커밋 수 · 최신 리비전 · 최신 메시지 (+ 전체 목록 펼치기), 변경이 없으면 빌드 시점 저장소 최신 리비전
  def deploy_changes(row)
    changes = row[:changes]
    return '-' if changes.nil?
    repo = @project.repository
    rev = ->(r, text = "r#{r}") { repo ? link_to_revision(r, repo, text: text) : text }
    if changes.empty?
      base = row[:baseline]
      return content_tag(:span, l(:label_deploy_no_changes), class: 'dep_none') unless base
      return content_tag(:span, safe_join([content_tag(:span, l(:label_deploy_no_changes), class: 'dep_none'),
                                           rev.(base.identifier, "#{l(:label_deploy_baseline)} r#{base.identifier}"),
                                           content_tag(:span, base.comments.to_s.lines.first.to_s.strip.truncate(60), class: 'dep_msg', title: base.comments)], ' '),
                         class: 'dep_chg')
    end
    top = changes.first
    head = safe_join([content_tag(:span, l(:label_deploy_commits, count: changes.size), class: 'dep_cnt'), rev.(top[:rev]),
                      content_tag(:span, top[:msg].lines.first.to_s.strip.truncate(60), class: 'dep_msg', title: top[:msg])], ' ')
    return content_tag(:span, head, class: 'dep_chg') if changes.size == 1
    list = content_tag(:ul, safe_join(changes.map { |c|
      content_tag(:li, safe_join([rev.(c[:rev]), content_tag(:span, c[:msg].lines.first.to_s.strip.truncate(80), title: c[:msg]),
                                  (content_tag(:span, c[:author], class: 'dep_who') if c[:author].present?)].compact, ' '))
    }))
    content_tag(:span, head, class: 'dep_chg') +
      content_tag(:details, content_tag(:summary, l(:label_deploy_changes_all)) + list, class: 'dep_more')
  end

  def deploy_by(by)
    by.is_a?(User) ? link_to_user(by) : (by.presence || '-')
  end
end
