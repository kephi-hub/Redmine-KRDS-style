# 간단한 엑셀(xlsx) 생성 — 추가 gem 없이 Redmine 에 들어 있는 rubyzip 으로 만듦
# sheets: [{ name:, header: [...], rows: [[...]], widths: [...] }] — 머리줄 굵게·배경, 첫 줄 고정, 자동 필터
require 'zip'

module DbManage
  module Xlsx
    module_function

    def build(sheets)
      buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
        put(zip, '[Content_Types].xml', content_types(sheets.size))
        put(zip, '_rels/.rels', ROOT_RELS)
        put(zip, 'xl/workbook.xml', workbook(sheets))
        put(zip, 'xl/_rels/workbook.xml.rels', workbook_rels(sheets.size))
        put(zip, 'xl/styles.xml', STYLES)
        sheets.each_with_index { |s, i| put(zip, "xl/worksheets/sheet#{i + 1}.xml", sheet(s)) }
      end
      buffer.string
    end

    def put(zip, name, xml)
      zip.put_next_entry(name)
      zip.write(xml)
    end

    def esc(value)
      value.to_s.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '').encode(xml: :text)
    end

    def col(index)
      s = +''
      n = index + 1
      while n.positive?
        n, r = (n - 1).divmod(26)
        s.prepend((65 + r).chr)
      end
      s
    end

    def cell(ref, value, style)
      if value.is_a?(Numeric)
        %(<c r="#{ref}" s="#{style}"><v>#{value}</v></c>)
      elsif value.nil? || value == ''
        %(<c r="#{ref}" s="#{style}"/>)
      else
        %(<c r="#{ref}" s="#{style}" t="inlineStr"><is><t xml:space="preserve">#{esc(value)}</t></is></c>)
      end
    end

    def sheet(s)
      last = col(s[:header].size - 1)
      rows = [s[:header]] + s[:rows]
      xml = +%(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n)
      xml << %(<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">)
      xml << %(<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>)
      xml << %(<sheetFormatPr defaultRowHeight="16.5"/>)
      xml << '<cols>' + s[:widths].each_with_index.map { |w, i| %(<col min="#{i + 1}" max="#{i + 1}" width="#{w}" customWidth="1"/>) }.join + '</cols>'
      xml << '<sheetData>'
      rows.each_with_index do |row, r|
        xml << %(<row r="#{r + 1}">)
        row.each_with_index { |v, c| xml << cell("#{col(c)}#{r + 1}", v, r.zero? ? 1 : 2) }
        xml << '</row>'
      end
      xml << '</sheetData>'
      xml << %(<autoFilter ref="A1:#{last}#{rows.size}"/>)
      xml << '</worksheet>'
    end

    def workbook(sheets)
      names = sheets.each_with_index.map { |s, i| %(<sheet name="#{esc(s[:name][0, 31])}" sheetId="#{i + 1}" r:id="rId#{i + 1}"/>) }.join
      filters = sheets.each_with_index.map do |s, i|
        %(<definedName name="_xlnm._FilterDatabase" localSheetId="#{i}" hidden="1">'#{esc(s[:name][0, 31])}'!$A$1:$#{col(s[:header].size - 1)}$#{s[:rows].size + 1}</definedName>)
      end.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{names}</sheets><definedNames>#{filters}</definedNames></workbook>)
    end

    def workbook_rels(count)
      rels = (1..count).map { |i| %(<Relationship Id="rId#{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet#{i}.xml"/>) }.join
      rels << %(<Relationship Id="rId#{count + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>)
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{rels}</Relationships>)
    end

    def content_types(count)
      sheets = (1..count).map { |i| %(<Override PartName="/xl/worksheets/sheet#{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>) }.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>#{sheets}</Types>)
    end

    ROOT_RELS = %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>).freeze

    # 0 기본, 1 머리줄(굵게·회색 배경·테두리·가운데), 2 본문(테두리·위쪽 정렬·줄바꿈)
    STYLES = <<~XML.freeze
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="2"><font><sz val="10"/><name val="맑은 고딕"/></font><font><b/><sz val="10"/><name val="맑은 고딕"/></font></fonts>
      <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFE6E8EA"/><bgColor indexed="64"/></patternFill></fill></fills>
      <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left style="thin"><color rgb="FFB1B8BE"/></left><right style="thin"><color rgb="FFB1B8BE"/></right><top style="thin"><color rgb="FFB1B8BE"/></top><bottom style="thin"><color rgb="FFB1B8BE"/></bottom><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
      </styleSheet>
    XML
  end
end
