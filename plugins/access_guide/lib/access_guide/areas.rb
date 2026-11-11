# 권한을 사람이 이해하는 "영역" 으로 묶은 기준표
# 등급: 관리(manage) > 작성(write) > 보기(view) > 없음 — 해당 등급의 권한을 하나라도 가지면 그 등급
module AccessGuide
  module Areas
  AREAS = [
    { key: 'project', view: %i[], write: %i[],
      manage: %i[add_project delete_project select_project_publicity edit_project close_project select_project_modules manage_members manage_versions add_subprojects manage_categories manage_public_queries manage_project_activities] },
    { key: 'issues', view: %i[view_issues view_issue_watchers],
      write: %i[save_queries add_issues edit_issues edit_own_issues add_issue_notes edit_own_issue_notes copy_issues manage_subtasks manage_issue_relations add_issue_watchers set_own_issues_private],
      manage: %i[delete_issues set_issues_private view_private_notes set_notes_private import_issues edit_issue_notes delete_issue_watchers] },
    { key: 'time', view: %i[view_time_entries], write: %i[log_time edit_own_time_entries],
      manage: %i[edit_time_entries log_time_for_other_users import_time_entries] },
    { key: 'documents', view: %i[view_documents], write: %i[add_documents edit_documents], manage: %i[delete_documents] },
    { key: 'files', view: %i[view_files], write: %i[manage_files], manage: %i[] },
    { key: 'boards', view: %i[view_messages view_message_watchers], write: %i[add_messages edit_own_messages delete_own_messages add_message_watchers],
      manage: %i[manage_boards edit_messages delete_messages delete_message_watchers] },
    { key: 'news', view: %i[view_news], write: %i[comment_news], manage: %i[manage_news] },
    { key: 'wiki', view: %i[view_wiki_pages view_wiki_edits export_wiki_pages view_wiki_page_watchers], write: %i[edit_wiki_pages add_wiki_page_watchers],
      manage: %i[manage_wiki delete_wiki_pages rename_wiki_pages protect_wiki_pages delete_wiki_pages_attachments delete_wiki_page_watchers] },
    { key: 'repository', view: %i[view_changesets browse_repository], write: %i[commit_access manage_related_issues], manage: %i[manage_repository] },
    { key: 'keys', view: %i[view_keys download_keys keys_all whitelist_keys], write: %i[edit_keys], manage: %i[manage_whitelist_keys export_keys] },
    { key: 'deploys', view: %i[view_deploys], write: %i[run_deploys], manage: %i[run_production_deploys manage_deploy_targets] },
    { key: 'glossary', view: %i[view_glossary], write: %i[manage_glossary], manage: %i[] },
    { key: 'db', view: %i[view_db_schema], write: %i[], manage: %i[manage_db_links] },
    { key: 'calendar', view: %i[view_calendar view_gantt], write: %i[], manage: %i[] },
  ].freeze

  LEVELS = %w(manage write view none).freeze

  def self.level(role, area)
    perms = role.permissions
    return 'manage' if (area[:manage] & perms).any?
    return 'write' if (area[:write] & perms).any?
    return 'view' if (area[:view] & perms).any?
    'none'
  end

  TIERS = %w(view write manage).freeze

  # 권한 설정 화면용: 영역별 [권한, 등급] 목록 (영역에 없는 권한은 '기타' — 읽기 권한이면 보기, 아니면 작성)
  def self.groups(permissions)
    by_name = permissions.index_by(&:name)
    used = []
    groups = AREAS.map do |area|
      items = TIERS.flat_map { |t| area[t.to_sym].filter_map { |n| [by_name[n], t] if by_name[n] } }
      used.concat(items.map { |p, _| p.name })
      { key: area[:key], items: items }
    end
    rest = permissions.reject { |p| used.include?(p.name) }
    groups << { key: 'other', items: rest.map { |p| [p, p.read? ? 'view' : 'write'] } } if rest.any?
    groups.reject { |g| g[:items].empty? }
  end

  # 역할이 가진 권한 중 가장 높은 등급
  def self.group_level(role, group)
    have = group[:items].select { |p, _| role.permissions.include?(p.name) }.map(&:last)
    %w(manage write view).find { |t| have.include?(t) } || 'none'
  end

  # 영역에 속한 권한 중 이 역할이 가진 것 (배지 설명용)
  def self.granted(role, area)
    (area[:view] + area[:write] + area[:manage]) & role.permissions
  end

  # 일감 상태 변경: 닫힌 상태(완료·거절)로 바꿀 수 있으면 "완료 처리", 전환이 있으면 "진행 처리", 없으면 없음
  def self.workflow_level(role, closed_ids)
    rows = WorkflowTransition.where(role_id: role.id, author: false, assignee: false)
    return 'none' unless rows.exists?
    rows.where(new_status_id: closed_ids).exists? ? 'manage' : 'write'
  end
  end
end
