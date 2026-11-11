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
      shown_all = {}
      picked.each do |t|
        id = ids[t[:name]]
        label = id == t[:name] ? id : %(#{id}["#{esc(t[:name])}"])
        shown = case columns
                when 'none' then []
                when 'keys' then (cols[t[:name]] || []).select { |c| c[:keys].any? || rel_cols.include?([t[:name], c[:name]]) }
                else cols[t[:name]] || []
                end
        shown_all[t[:name]] = shown
        out << "  #{label} {\n"
        shown.each do |c|
          comment = c[:comment].to_s.strip
          name = c[:name].to_s
          unless name.match?(NAME)
            comment = [name, comment.presence].compact.join(' · ')
            name = "col_#{c[:position]}"
          end
          ks = c[:keys] & %w(PK FK UK)
          out << "    #{type_word(c[:type])} #{name}#{" #{ks.join(', ')}" if ks.any?}#{%( "#{esc(comment.truncate(40))}") if comment.present?}\n"
        end
        out << "  }\n"
      end
      rels.each do |r|
        line = r[:inferred] ? '..' : '--'
        out << %(  #{ids[r[:from]]} ||#{line}#{r[:one] ? 'o|' : 'o{'} #{ids[r[:to]]} : "#{esc(r[:column])}"\n)
      end
      { mermaid: out, tables: picked, relations: rels, ids: ids, shown: shown_all }
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

    # draw.io(diagrams.net) 파일 — 테이블은 ER 표 모양, 관계는 ER 선(FK 실선·추정 점선). 연결된 테이블끼리 가까이, 4열 격자
    def drawio(erd, title)
      tables = erd[:tables]
      rels = erd[:relations]
      # 관계로 이어진 테이블을 한 무리로 (먼저 나온 무리부터)
      adj = Hash.new { |h, k| h[k] = [] }
      rels.each { |r| adj[r[:from]] << r[:to]; adj[r[:to]] << r[:from] }
      order = []
      seen = {}
      tables.map { |t| t[:name] }.sort_by { |n| -adj[n].size }.each do |start|
        next if seen[start]
        queue = [start]
        until queue.empty?
          n = queue.shift
          next if seen[n]
          seen[n] = true
          order << n
          queue.concat(adj[n].sort)
        end
      end
      by_name = tables.index_by { |t| t[:name] }
      cols = 4
      width = 280
      heights = Array.new(cols, 40)
      cells = []
      ids = {}
      order.each_with_index do |name, i|
        t = by_name[name]
        rows = erd[:shown][name] || []
        h = 30 + rows.size * 24
        c = heights.each_with_index.min_by(&:first).last
        x = 40 + c * (width + 80)
        y = heights[c]
        heights[c] += h + 60
        id = "t#{i + 1}"
        ids[name] = id
        label = t[:comment].present? ? "#{name} (#{t[:comment]})" : name
        cells << %(<mxCell id="#{id}" value="#{xml_attr(label)}" style="swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;startSize=30;horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;marginBottom=0;fillColor=#ecf2fe;strokeColor=#256ef4;fontColor=#1e2124;" vertex="1" parent="1"><mxGeometry x="#{x}" y="#{y}" width="#{width}" height="#{h}" as="geometry"/></mxCell>)
        rows.each_with_index do |col, j|
          keys = (col[:keys] & %w(PK FK UK)).join(',')
          text = [keys.presence, col[:name], ": #{col[:type]}"].compact.join(' ')
          text += "  — #{col[:comment]}" if col[:comment].present?
          style = 'text;strokeColor=none;fillColor=none;align=left;verticalAlign=middle;spacingLeft=6;spacingRight=4;overflow=hidden;rotatable=0;points=[[0,0.5],[1,0.5]];portConstraint=eastwest;'
          style += 'fontStyle=1;' if col[:keys].include?('PK')
          cells << %(<mxCell id="#{id}c#{j + 1}" value="#{xml_attr(text)}" style="#{style}" vertex="1" parent="#{id}"><mxGeometry y="#{30 + j * 24}" width="#{width}" height="24" as="geometry"/></mxCell>)
        end
      end
      rels.each_with_index do |r, i|
        next unless ids[r[:from]] && ids[r[:to]]
        style = "edgeStyle=entityRelationEdgeStyle;fontSize=11;html=1;endArrow=#{r[:one] ? 'ERzeroToOne' : 'ERzeroToMany'};startArrow=ERmandOne;endFill=0;startFill=0;strokeColor=#6d7882;"
        style += 'dashed=1;' if r[:inferred]
        cells << %(<mxCell id="e#{i + 1}" value="#{xml_attr(r[:column])}" style="#{style}" edge="1" parent="1" source="#{ids[r[:from]]}" target="#{ids[r[:to]]}"><mxGeometry relative="1" as="geometry"/></mxCell>)
      end
      <<~XML
        <mxfile host="Redmine" type="device">
          <diagram name="#{xml_attr(title)}" id="erd">
            <mxGraphModel dx="1200" dy="800" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="0" pageScale="1" math="0" shadow="0">
              <root>
                <mxCell id="0"/>
                <mxCell id="1" parent="0"/>
                #{cells.join("\n          ")}
              </root>
            </mxGraphModel>
          </diagram>
        </mxfile>
      XML
    end

    def xml_attr(text)
      text.to_s.encode(xml: :attr)[1..-2]
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
