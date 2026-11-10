module AccessOverviewHelper
  def access_level_tag(level, title = nil)
    content_tag(:span, l("label_access_level_#{level}"), class: "ag_lv lv_#{level}", title: title.presence)
  end

  def access_perm_names(perms)
    perms.map { |p| l("permission_#{p}", default: p.to_s.humanize) }.join(', ')
  end
end
