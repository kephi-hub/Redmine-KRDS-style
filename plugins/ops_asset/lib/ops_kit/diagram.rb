# 연계 구성도 — 우리 시스템을 가운데 두고 상대 시스템별로 화살표(송신 →, 수신 ←, 양방향 ↔), 선 글자는 ID·방식
module OpsKit
  module Diagram
    module_function

    def esc(text)
      text.to_s.gsub('"', '＂').gsub(/[\r\n]+/, ' ').truncate(60)
    end

    def mermaid(system, list)
      lines = ['flowchart LR', "  oa_sys[\"#{esc(system)}\"]:::oa_us"]
      partners = list.map(&:partner).uniq
      partners.each_with_index { |p, i| lines << "  oa_p#{i}[\"#{esc(p)}\"]:::oa_them" }
      list.each do |f|
        i = partners.index(f.partner)
        label = esc("#{f.code} #{OpsKit::Sheet::LABEL['protocol'][f.protocol]}#{" · #{OpsKit::Sheet::LABEL['cycle'][f.cycle]}" if f.cycle != 'realtime'}")
        lines << case f.direction
                 when 'send' then "  oa_sys -->|\"#{label}\"| oa_p#{i}"
                 when 'recv' then "  oa_p#{i} -->|\"#{label}\"| oa_sys"
                 else "  oa_sys <-->|\"#{label}\"| oa_p#{i}"
                 end
      end
      lines << '  classDef oa_us fill:#ecf2fe,stroke:#256ef4,stroke-width:2px,color:#083891'
      lines << '  classDef oa_them fill:#ffffff,stroke:#8a949e,color:#1e2124'
      lines.join("\n")
    end

    def xml_attr(text)
      text.to_s.encode(xml: :attr)[1..-2]
    end

    # draw.io: 가운데 우리 시스템, 둘레에 상대 시스템을 원형으로
    def drawio(system, list)
      partners = list.map(&:partner).uniq
      cells = []
      cx = 500
      cy = 360
      cells << %(<mxCell id="sys" value="#{xml_attr(system)}" style="rounded=1;whiteSpace=wrap;fillColor=#ecf2fe;strokeColor=#256ef4;strokeWidth=2;fontStyle=1;" vertex="1" parent="1"><mxGeometry x="#{cx - 90}" y="#{cy - 30}" width="180" height="60" as="geometry"/></mxCell>)
      r = [220, 80 + partners.size * 25].max
      partners.each_with_index do |p, i|
        a = 2 * Math::PI * i / [partners.size, 1].max
        x = (cx + r * Math.cos(a) - 80).round
        y = (cy + r * Math.sin(a) - 25).round
        cells << %(<mxCell id="p#{i}" value="#{xml_attr(p)}" style="rounded=1;whiteSpace=wrap;fillColor=#ffffff;strokeColor=#8a949e;" vertex="1" parent="1"><mxGeometry x="#{x}" y="#{y}" width="160" height="50" as="geometry"/></mxCell>)
      end
      list.each_with_index do |f, n|
        i = partners.index(f.partner)
        src, dst = f.direction == 'recv' ? ["p#{i}", 'sys'] : ['sys', "p#{i}"]
        arrows = f.direction == 'both' ? 'startArrow=classic;endArrow=classic;' : 'endArrow=classic;'
        label = "#{f.code} #{OpsKit::Sheet::LABEL['protocol'][f.protocol]}"
        cells << %(<mxCell id="e#{n}" value="#{xml_attr(label)}" style="#{arrows}html=1;fontSize=10;" edge="1" parent="1" source="#{src}" target="#{dst}"><mxGeometry relative="1" as="geometry"/></mxCell>)
      end
      %(<mxfile><diagram name="#{xml_attr(system)}"><mxGraphModel><root><mxCell id="0"/><mxCell id="1" parent="0"/>#{cells.join}</root></mxGraphModel></diagram></mxfile>)
    end
  end
end
