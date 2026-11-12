# 일감 목록: "메뉴" 열과 검색조건 (메뉴를 고르면 하위 메뉴에 연결된 일감까지)
# QueryColumn 은 Redmine app/models/query.rb 안에 있어 Query 를 먼저 불러옴
::Query

module MenuTree
  class MenuQueryColumn < ::QueryColumn
    def initialize
      super(:menu_items, caption: :label_menu_item)
    end

    def value_object(issue)
      issue.menu_items.to_a
    end
  end

  module IssueQueryPatch
    def initialize_available_filters
      super
      return unless MenuTree.enabled_for?(project)
      add_available_filter 'menu_item_id', type: :list_optional, name: l(:label_menu_item),
                           values: lambda { MenuItem.ordered(project).map { |m, d| ["#{'— ' * d}#{m.pick_label(d)}", m.id.to_s] } }
    end

    def available_columns
      cols = super
      if MenuTree.enabled_for?(project) && cols.none? { |c| c.name == :menu_items }
        cols << MenuQueryColumn.new
      end
      cols
    end

    def sql_for_menu_item_id_field(_field, operator, value)
      t = Issue.table_name
      case operator
      when '*' then "#{t}.id IN (SELECT issue_id FROM menu_item_issues)"
      when '!*' then "#{t}.id NOT IN (SELECT issue_id FROM menu_item_issues)"
      else
        ids = value.map(&:to_i)
        if project
          by_parent = MenuItem.where(project_id: project.id).to_a.group_by(&:parent_id)
          ids |= MenuItem.where(id: ids).flat_map { |m| m.descendant_ids(by_parent) }
        end
        ids = [0] if ids.empty?
        "#{t}.id #{operator == '!' ? 'NOT IN' : 'IN'} (SELECT issue_id FROM menu_item_issues WHERE menu_item_id IN (#{ids.join(',')}))"
      end
    end
  end
end
