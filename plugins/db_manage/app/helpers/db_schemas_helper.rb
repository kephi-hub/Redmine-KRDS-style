module DbSchemasHelper
  # PK·UK·FK 배지 (FK 는 참조 대상 툴팁)
  def db_key_tags(col)
    safe_join(col[:keys].map { |k| content_tag(:span, k, class: "db_key db_#{k.downcase}", title: (k == 'FK' ? "→ #{col[:ref]}" : nil)) }, ' ')
  end

  def db_term_tag(status, term)
    case status
    when :ok then content_tag(:span, term.name, class: 'db_term db_ok', title: term.definition.to_s.truncate(200))
    when :type then content_tag(:span, l(:label_db_term_type, expected: term.type_label), class: 'db_term db_type', title: term.name)
    else content_tag(:span, l(:label_db_term_missing), class: 'db_term db_missing')
    end
  end

  def db_link_label(link)
    safe_join([link.name, (content_tag(:span, l(:label_db_production), class: 'dep_prod') if link.production?)].compact, ' ')
  end

  def db_link_info(link)
    s = link.db_server
    "#{s.adapter_label} · #{s.host}:#{s.port}/#{s.database_name}#{" · #{l(:field_db_schema)} #{link.schema}" if s.adapter == 'postgresql'}"
  end

  def db_number(n)
    n.nil? ? '-' : number_with_delimiter(n)
  end

  # 프로젝트 DB 화면 위쪽 탭 (DB 별 + 비교)
  def db_tabs(current)
    items = @links.map { |l| [db_link_label(l), project_db_schemas_path(@project, link: l.id), current == l] }
    items << [l(:label_db_compare), project_db_compare_path(@project), current == :compare] if @links.size > 1
    content_tag(:div, class: 'tabs') do
      content_tag(:ul, safe_join(items.map { |label, url, on| content_tag(:li, link_to(label, url, class: (on ? 'selected' : nil))) }))
    end
  end

  # 비교 표의 값 표시
  def db_diff_value(col, field)
    v = col[field]
    case field
    when :nullable then v ? 'NULL 허용' : 'NOT NULL'
    when :keys then v.presence ? v.join(', ') : '-'
    else v.nil? || v == '' ? '-' : v.to_s
    end
  end
end
