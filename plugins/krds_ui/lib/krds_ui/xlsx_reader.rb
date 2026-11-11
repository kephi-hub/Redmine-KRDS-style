# 엑셀(xlsx) 첫 시트를 문자열 2차원 배열로 읽음 — rubyzip·nokogiri (Redmine 에 포함) 만 사용
# 빈 칸은 nil, 숫자는 정수면 "3" 처럼, 날짜 서식은 따로 변환하지 않음
require 'zip'
require 'nokogiri'

module KrdsUi
  module XlsxReader
    module_function

    NS = { 'm' => 'http://schemas.openxmlformats.org/spreadsheetml/2006/main' }.freeze

    # (rubyzip 의 open_buffer 는 블록 결과가 아니라 버퍼를 돌려주므로 결과를 따로 받음)
    def read(data)
      result = nil
      Zip::File.open_buffer(StringIO.new(data)) do |zip|
        result = read_zip(zip)
      end
      result
    rescue Zip::Error, Nokogiri::XML::SyntaxError
      nil
    end

    def read_zip(zip)
      begin
        shared = []
        if (e = zip.find_entry('xl/sharedStrings.xml'))
          Nokogiri::XML(e.get_input_stream.read).xpath('//m:si', NS).each { |si| shared << si.xpath('.//m:t', NS).map(&:text).join }
        end
        sheet = first_sheet(zip)
        return [] unless sheet
        rows = []
        Nokogiri::XML(zip.read(sheet)).xpath('//m:sheetData/m:row', NS).each do |row|
          r = (row['r'] || rows.size + 1).to_i - 1
          cells = []
          row.xpath('m:c', NS).each_with_index do |c, i|
            idx = c['r'] ? col_index(c['r']) : i
            v = case c['t']
                when 's' then shared[c.at_xpath('m:v', NS)&.text.to_i]
                when 'inlineStr' then c.xpath('.//m:t', NS).map(&:text).join
                when 'b' then c.at_xpath('m:v', NS)&.text == '1' ? 'TRUE' : 'FALSE'
                else
                  t = c.at_xpath('m:v', NS)&.text
                  t && t.match?(/\A-?\d+\.0+\z/) ? t.to_i.to_s : t
                end
            cells[idx] = v.to_s.strip.presence
          end
          rows[r] = cells
        end
        rows.map { |r| r || [] }
      end
    end

    def first_sheet(zip)
      wb = Nokogiri::XML(zip.read('xl/workbook.xml'))
      rid = wb.at_xpath('//m:sheets/m:sheet', NS)&.attribute_with_ns('id', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')&.value
      if rid && (rels = zip.find_entry('xl/_rels/workbook.xml.rels'))
        target = Nokogiri::XML(rels.get_input_stream.read).remove_namespaces!.at_xpath("//Relationship[@Id='#{rid}']")&.[]('Target')
        if target
          path = target.start_with?('/') ? target.delete_prefix('/') : "xl/#{target}"
          return path if zip.find_entry(path)
        end
      end
      'xl/worksheets/sheet1.xml' if zip.find_entry('xl/worksheets/sheet1.xml')
    end

    def col_index(ref)
      letters = ref[/\A[A-Z]+/].to_s
      letters.each_char.reduce(0) { |n, ch| n * 26 + (ch.ord - 64) } - 1
    end
  end
end
