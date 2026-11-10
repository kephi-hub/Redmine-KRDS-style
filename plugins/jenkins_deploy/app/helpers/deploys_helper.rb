module DeploysHelper
  # 상태 배지 (성공·실패·진행 중 등)
  def deploy_status_tag(status)
    content_tag(:span, l("label_deploy_status_#{status}"), class: "dep_st st_#{status}")
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
