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

  def deploy_by(by)
    by.is_a?(User) ? link_to_user(by) : (by.presence || '-')
  end
end
