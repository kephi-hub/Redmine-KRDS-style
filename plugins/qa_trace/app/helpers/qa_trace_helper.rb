# 요구사항·테스트 화면 공통 표시 (분류·상태·결과 배지, 진행 막대)
module QaTraceHelper
  def qa_cat_label(cat)
    name = QaRequirement::CATEGORY_NAMES[cat]
    name ? "#{cat} #{name}" : cat.to_s
  end

  def qa_cat_options
    QaRequirement::CATEGORIES.map { |c| [qa_cat_label(c), c] }
  end

  def qa_status_label(status)
    l("label_qa_status_#{status}")
  end

  def qa_status_badge(status)
    content_tag(:span, qa_status_label(status), class: 'qa_badge', data: { k: status })
  end

  def qa_priority_label(priority)
    l("label_qa_priority_#{priority}")
  end

  def qa_kind_label(kind)
    kind.present? ? l("label_qa_kind_#{kind}") : l(:label_qa_kind_all)
  end

  def qa_result_label(result)
    l("label_qa_result_#{result}")
  end

  def qa_result_badge(result, retest = false)
    return content_tag(:span, l(:label_qa_retest), class: 'qa_badge', data: { k: 'retest' }) if retest
    content_tag(:span, qa_result_label(result), class: 'qa_badge', data: { k: result })
  end

  def qa_risk_badge(risk)
    content_tag(:span, l("label_qa_risk_#{risk}"), class: 'qa_badge', data: { k: risk })
  end

  def qa_bar(done, total)
    pct = total.to_i.positive? ? done * 100 / total : 0
    content_tag(:span, content_tag(:span, '', style: "width:#{pct}%"), class: 'mt_bar') +
      content_tag(:span, "#{done}/#{total}", class: 'mt_pct')
  end

  # 메뉴 선택 목록: [[경로, id], …] (뎁스만큼 들여씀)
  def qa_menu_options(ordered)
    ordered.map { |m, d| ["#{"  " * d}#{m.name}#{" (#{m.screen_id})" if m.screen_id}", m.id] }
  end

  # 변경 이력 한 줄 설명
  def qa_log_text(field, old, new)
    case field
    when '_create' then l(:label_qa_log_created)
    when '_import' then l(:label_qa_log_imported)
    when 'menus', 'issues', 'cases'
      "#{l("label_qa_field_#{field}")}: #{old.presence || '-'} → #{new.presence || '-'}"
    when 'status' then "#{l(:field_status)}: #{qa_status_label(old)} → #{qa_status_label(new)}"
    when 'priority' then "#{l(:label_qa_priority)}: #{qa_priority_label(old)} → #{qa_priority_label(new)}"
    when 'description' then l(:label_qa_log_description)
    when 'parent_id'
      names = QaRequirement.where(id: [old, new].compact).pluck(:id, :code).to_h
      "#{l(:label_qa_parent)}: #{names[old.to_i] || '-'} → #{names[new.to_i] || '-'}"
    else "#{l("label_qa_field_#{field}", default: field)}: #{old.presence || '-'} → #{new.presence || '-'}"
    end
  end
end
