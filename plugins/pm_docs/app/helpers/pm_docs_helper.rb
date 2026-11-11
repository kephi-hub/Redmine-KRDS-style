# 산출물 · 변경요청 · 프로그램 · 회의록 · 이슈·위험 화면 공통 표시
module PmDocsHelper
  def pm_label(group, key)
    PmKit::Sheet::LABEL[group][key] || key.to_s
  end

  def pm_options(group, keys)
    keys.map { |k| [pm_label(group, k), k] }
  end

  def pm_badge(text, key)
    content_tag(:span, text, class: 'pm_badge', data: { k: key })
  end

  def pm_time(t)
    t && t.in_time_zone(ActiveSupport::TimeZone['Asia/Seoul']).strftime('%Y-%m-%d %H:%M')
  end

  def pm_members(project)
    project.users.active.sort_by(&:name)
  end

  def pm_bar(done, total)
    pct = total.to_i.positive? ? done * 100 / total : 0
    content_tag(:span, content_tag(:span, '', style: "width:#{pct}%"), class: 'mt_bar') + content_tag(:span, "#{pct}%", class: 'mt_pct')
  end
end
