# ERD — 스키마 정보(Connector#snapshot)로 Mermaid erDiagram 텍스트를 만듦
# - 실선: FK 제약, 점선: 추정 관계(다른 테이블의 단일 PK 와 이름이 같은 컬럼, 후보가 하나일 때만)
# - Mermaid 문법 제한: 타입의 쉼표·공백, 영문 아닌 테이블·컬럼 이름은 바꿔 씀
#   (테이블은 별칭 "원래 이름", 컬럼은 col_순번 + 설명에 원래 이름). 뷰는 ERD 에서 뺌
module DbManage
  module Erd
    module_function

    NAME = /\A[A-Za-z_][A-Za-z0-9_-]*\z/

    # columns: 'all' | 'keys' | 'none'
    def build(snap, tables: nil, columns: 'all', inferred: true)
      all = snap[:tables].reject { |t| t[:view] }
      picked = tables ? all.select { |t| tables.include?(t[:name]) } : all
      names = picked.map { |t| t[:name] }
      cols = snap[:columns]
      ids = {}
      picked.each_with_index { |t, i| ids[t[:name]] = t[:name].match?(NAME) ? t[:name] : "t#{i + 1}" }

      rels = []
      picked.each do |t|
        (cols[t[:name]] || []).each do |c|
          next unless c[:keys].include?('FK') && c[:ref]
          parent = c[:ref].split('.').first
          next unless names.include?(parent)
          rels << { from: parent, to: t[:name], column: c[:name], one: (c[:keys] & %w(PK UK)).any? && single_key?(cols[t[:name]], c), inferred: false }
        end
      end
      if inferred
        pk = {}
        picked.each do |t|
          keys = (cols[t[:name]] || []).select { |c| c[:keys].include?('PK') }
          (pk[keys.first[:name].upcase] ||= []) << t[:name] if keys.size == 1
        end
        picked.each do |t|
          (cols[t[:name]] || []).each do |c|
            next if c[:keys].include?('FK')
            cands = (pk[c[:name].upcase] || []) - [t[:name]]
            next unless cands.size == 1
            next if (pk[c[:name].upcase] || []).include?(t[:name]) && (cols[t[:name]] || []).count { |x| x[:keys].include?('PK') } == 1
            next if rels.any? { |r| r[:from] == cands.first && r[:to] == t[:name] && r[:column] == c[:name] }
            rels << { from: cands.first, to: t[:name], column: c[:name], one: false, inferred: true }
          end
        end
      end
      rel_cols = rels.map { |r| [r[:to], r[:column]] }

      out = +"erDiagram\n"
      picked.each do |t|
        id = ids[t[:name]]
        label = id == t[:name] ? id : %(#{id}["#{esc(t[:name])}"])
        shown = case columns
                when 'none' then []
                when 'keys' then (cols[t[:name]] || []).select { |c| c[:keys].any? || rel_cols.include?([t[:name], c[:name]]) }
                else cols[t[:name]] || []
                end
        out << "  #{label} {\n"
        shown.each do |c|
          comment = c[:comment].to_s.strip
          name = c[:name].to_s
          unless name.match?(NAME)
            comment = [name, comment.presence].compact.join(' · ')
            name = "col_#{c[:position]}"
          end
          out << "    #{type_word(c[:type])} #{name}#{" #{c[:keys].join(', ')}" if c[:keys].any?}#{%( "#{esc(comment.truncate(40))}") if comment.present?}\n"
        end
        out << "  }\n"
      end
      rels.each do |r|
        line = r[:inferred] ? '..' : '--'
        out << %(  #{ids[r[:from]]} ||#{line}#{r[:one] ? 'o|' : 'o{'} #{ids[r[:to]]} : "#{esc(r[:column])}"\n)
      end
      { mermaid: out, tables: picked, relations: rels, ids: ids }
    end

    def single_key?(columns, col)
      key = col[:keys].include?('PK') ? 'PK' : 'UK'
      (columns || []).count { |c| c[:keys].include?(key) } == 1
    end

    # 타입: varchar(20) 그대로, decimal(12,2) → decimal(12-2), character varying(20) → varchar(20)
    def type_word(type)
      base, len = DbManage::Analysis.split_type(type)
      w = base.to_s.tr(' ', '_')
      w += "(#{len.tr(',', '-')})" if len.present?
      w = w.gsub(/[^A-Za-z0-9_\-()\[\]]/, '_')
      w.match?(/\A[A-Za-z_]/) ? w : "t_#{w}"
    end

    def esc(text)
      text.to_s.tr('"', "'").gsub(/[\r\n]+/, ' ')
    end

    # 내려받기용 마크다운 (깃허브·VS Code·Redmine 위키에서 그림으로 보임)
    def markdown(title, info, erd)
      md = +"# #{title}\n\n#{info}\n\n```mermaid\n#{erd[:mermaid]}```\n\n"
      md << "- 실선: FK 제약 · 점선: 추정 관계(같은 이름의 PK 컬럼)\n\n" if erd[:relations].any?(&:itself)
      md << "| 테이블 | 설명 |\n|---|---|\n"
      erd[:tables].each { |t| md << "| #{t[:name]} | #{t[:comment].to_s.tr('|', '/')} |\n" }
      md
    end
  end
end
