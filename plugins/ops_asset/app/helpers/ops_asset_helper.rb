# 자산·스케줄러·점검·장애·인터페이스 화면 공통 표시
module OpsAssetHelper
  def oa_label(group, key)
    OpsKit::Sheet::LABEL[group][key.to_s] || key.to_s
  end

  def oa_options(group, keys)
    keys.map { |k| [oa_label(group, k), k] }
  end

  # 만료 배지 (data-k 로 색)
  def oa_expiry(asset)
    state = asset.expiry_state
    return content_tag(:span, '-', class: 'db_dim') if state == :none
    d = asset.days_left
    text = d.negative? ? l(:label_oa_expired_days, count: -d) : (d.zero? ? l(:label_oa_today) : l(:label_oa_days_left, count: d))
    safe_join([content_tag(:span, format_date(asset.expires_on), class: 'oa_date'), content_tag(:span, text, class: 'oa_badge', data: { k: state })], ' ')
  end

  def oa_badge(text, key)
    content_tag(:span, text, class: 'oa_badge', data: { k: key })
  end

  def asset_kpi(all)
    states = all.map(&:expiry_state)
    { all: all.size, expired: states.count(:expired), soon7: states.count(:soon7), soon30: states.count(:soon30) + states.count(:soon7),
      server: all.count { |a| a.kind == 'server' }, cert: all.count { |a| %w(domain cert).include?(a.kind) } }
  end

  def oa_time(t)
    t && t.in_time_zone(OpsKit::Cron.zone).strftime('%Y-%m-%d %H:%M')
  end

  def oa_minutes(min)
    return '-' if min.nil?
    min >= 60 ? l(:label_oa_hm, h: min / 60, m: min % 60) : l(:label_oa_m, m: min)
  end

  # 자산 선택 목록 (프로젝트에서 보이는 자산)
  def oa_asset_options(project, kinds = nil)
    list = OpsAsset.for_project(project).where(active: true).sorted
    list = list.where(kind: kinds) if kinds
    list.map { |a| ["#{oa_label('kind', a.kind)} · #{a.name}#{" (#{a.address})" if a.address.present?}", a.id] }
  end

  # 점검·장애 탭
  def oa_log_tabs(current)
    items = [[l(:label_oa_incidents), project_ops_incidents_path(@project), :incidents],
             [l(:label_oa_checks), project_ops_checks_path(@project), :checks],
             [l(:label_oa_report), project_ops_report_path(@project), :report]]
    content_tag(:div, class: 'tabs') do
      content_tag(:ul, safe_join(items.map { |label, url, key| content_tag(:li, link_to(label, url, class: (current == key ? 'selected' : nil))) }))
    end
  end

  def oa_schedule_tabs(current)
    items = [[l(:label_oa_sched_list), project_ops_schedules_path(@project), :list],
             [l(:label_oa_timeline), project_ops_schedules_timeline_path(@project), :timeline]]
    content_tag(:div, class: 'tabs') do
      content_tag(:ul, safe_join(items.map { |label, url, key| content_tag(:li, link_to(label, url, class: (current == key ? 'selected' : nil))) }))
    end
  end

  def oa_interface_tabs(current)
    items = [[l(:label_oa_if_list), project_ops_interfaces_path(@project), :list],
             [l(:label_oa_if_diagram), project_ops_interfaces_diagram_path(@project), :diagram]]
    content_tag(:div, class: 'tabs') do
      content_tag(:ul, safe_join(items.map { |label, url, key| content_tag(:li, link_to(label, url, class: (current == key ? 'selected' : nil))) }))
    end
  end
end
