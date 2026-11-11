module DbSchemasHelper
  # PK·UK·FK 배지 (FK 는 참조 대상 툴팁)
  def db_key_tags(col)
    safe_join(col[:keys].map { |k| content_tag(:span, k, class: "db_key db_#{k.downcase}", title: (k == 'FK' ? "→ #{col[:ref]}" : (k == 'IX' ? l(:label_db_indexed) : nil))) }, ' ')
  end

  def db_term_tag(status, term)
    case status
    when :ok then content_tag(:span, term.name, class: 'db_term db_ok', title: term.definition.to_s.truncate(200))
    when :type then content_tag(:span, l(:label_db_term_type, expected: term.type_label), class: 'db_term db_type', title: term.name)
    else content_tag(:span, l(:label_db_term_missing), class: 'db_term db_missing')
    end
  end

  # 개인정보 분류 배지 (data-k 로 색)
  def db_pv_badge(category, encryption = nil)
    title = encryption ? "#{l(:label_db_pv_encryption)}: #{l("label_db_pv_enc_#{encryption}")}" : nil
    content_tag(:span, l("label_db_pv_cat_#{category}"), class: 'db_pv', data: { k: category }, title: title)
  end

  # 판정 배지: 정상·경고·확인 필요·DB 에 없음
  def db_pv_judge(judge, gone = false)
    return content_tag(:span, l(:label_db_pv_gone), class: 'db_pvj', data: { k: 'gone' }) if gone
    return ''.html_safe if judge == :na
    content_tag(:span, l("label_db_pv_judge_#{judge}"), class: 'db_pvj', data: { k: judge })
  end

  def db_pv_options(blank_label = nil)
    opts = DbPrivacyColumn::CATEGORIES.map { |k| [l("label_db_pv_cat_#{k}"), k] }
    blank_label ? [[blank_label, '']] + opts : opts
  end

  def db_pv_enc_options
    DbPrivacyColumn::ENCRYPTIONS.map { |k| [l("label_db_pv_enc_#{k}"), k] }
  end

  def db_link_label(link)
    safe_join([link.name, (content_tag(:span, l(:label_db_production), class: 'dep_prod') if link.production?)].compact, ' ')
  end

  def db_link_info(link)
    s = link.db_server
    "#{s.adapter_label} · #{s.host}:#{s.port}/#{s.database_name}#{" · #{l(:field_db_schema)} #{link.schema}" unless s.adapter == 'mariadb'}"
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

  # 종류 탭 이름·개수
  def db_kind_label(kind)
    l("label_db_kind_#{kind}")
  end

  def db_kind_items(snap, kind)
    case kind
    when 'table' then snap[:tables].reject { |t| t[:view] }
    when 'view' then snap[:tables].select { |t| t[:view] && !t[:matview] }
    when 'matview' then snap[:tables].select { |t| t[:matview] }
    else snap.dig(:objects, kind)
    end
  end

  # 목록이 비었을 때 DB 종류별 필요한 권한 안내 (조사 결과: MariaDB·MySQL 은 조회 전용 계정에 안 보이는 객체가 있음)
  def db_kind_hint(flavor, kind)
    key = "text_db_hint_#{flavor}_#{kind}"
    I18n.exists?(key, current_language) ? l(key) : nil
  end

  def db_object_path(link, kind, key)
    project_db_object_path(@project, link, kind, key)
  end

  def db_status_tag(status)
    return '' if status.blank?
    on = status.to_s.start_with?('ENABLED')
    content_tag(:span, on ? l(:label_db_enabled) : l(:label_db_disabled), class: "db_term #{on ? 'db_ok' : 'db_missing'}")
  end
end
