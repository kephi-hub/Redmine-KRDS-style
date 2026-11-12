# 간단한 파워포인트(pptx) 생성 — 추가 gem 없이 rubyzip 으로 (화면 설계서 등)
# 테마·마스터·레이아웃은 config/pptx_base 의 고정 파일(pptxgenjs 로 만든 16:9 와이드 빈 문서, 글꼴 맑은 고딕)
# 좌표는 인치(16:9 와이드 = 13.333 × 7.5). 글자 크기는 pt.
#   deck = KrdsUi::Pptx.new(title: '화면 설계서', author: '김민준')
#   s = deck.slide
#   s.text(0.5, 0.4, 8, 0.6, '제목', size: 24, bold: true)
#   s.image(png_bytes, 'png', 0.5, 1.2, 8, 5, crop: { t: 0, b: 40_000 }, border: 'CDD1D5')
#   s.table(9, 1.2, [1.2, 2.6], [[{ text: '화면 ID', bold: true, fill: 'EEF2F7' }, 'PT-001']], row_h: 0.32, size: 10)
#   deck.to_s  # pptx 바이트
require 'zip'
require 'securerandom'

module KrdsUi
  class Pptx
    EMU = 914_400
    W = 12_192_000
    H = 6_858_000
    BASE = File.expand_path('../../config/pptx_base', __dir__)
    FONT = '맑은 고딕'
    NS = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" ' \
         'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
    REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'

    def self.emu(inch)
      (inch.to_f * EMU).round
    end

    def self.esc(value)
      value.to_s.gsub(/[\x00-\x08\x0B\x0C\x0E-\x1F]/, '').encode(xml: :text)
    end

    attr_reader :slides

    def initialize(title: '', author: '')
      @title = title
      @author = author
      @slides = []
      @media = []
    end

    def slide
      s = Slide.new(self, @slides.size + 1)
      @slides << s
      s
    end

    # 그림 파일을 문서에 넣고 이름 돌려줌 (ppt/media/imageN.ext)
    def add_media(data, ext)
      name = "image#{@media.size + 1}.#{ext}"
      @media << [name, data]
      name
    end

    def to_s
      buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
        put(zip, '[Content_Types].xml', content_types)
        put(zip, '_rels/.rels', root_rels)
        put(zip, 'docProps/app.xml', app_xml)
        put(zip, 'docProps/core.xml', core_xml)
        put(zip, 'ppt/presentation.xml', presentation_xml)
        put(zip, 'ppt/_rels/presentation.xml.rels', presentation_rels)
        { 'ppt/slideMasters/slideMaster1.xml' => 'slideMaster1.xml', 'ppt/slideLayouts/slideLayout1.xml' => 'slideLayout1.xml', 'ppt/theme/theme1.xml' => 'theme1.xml',
          'ppt/presProps.xml' => 'presProps.xml', 'ppt/viewProps.xml' => 'viewProps.xml', 'ppt/tableStyles.xml' => 'tableStyles.xml' }.each do |path, file|
          put(zip, path, File.read(File.join(BASE, file), encoding: 'UTF-8'))
        end
        put(zip, 'ppt/slideMasters/_rels/slideMaster1.xml.rels', rels([['rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml'], ['rId2', 'theme', '../theme/theme1.xml']]))
        put(zip, 'ppt/slideLayouts/_rels/slideLayout1.xml.rels', rels([['rId1', 'slideMaster', '../slideMasters/slideMaster1.xml']]))
        @slides.each do |s|
          put(zip, "ppt/slides/slide#{s.index}.xml", s.to_xml)
          put(zip, "ppt/slides/_rels/slide#{s.index}.xml.rels", rels([['rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml']] + s.media_rels))
        end
        @media.each { |name, data| put(zip, "ppt/media/#{name}", data) }
      end
      buffer.string
    end

    private

    def put(zip, name, data)
      zip.put_next_entry(name)
      zip.write(data)
    end

    def rels(list)
      body = list.map { |id, type, target| %(<Relationship Id="#{id}" Type="#{REL}/#{type}" Target="#{target}"/>) }.join
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{body}</Relationships>)
    end

    def content_types
      ct = 'application/vnd.openxmlformats-officedocument.presentationml'
      over = [['/ppt/presentation.xml', "#{ct}.presentation.main+xml"], ['/ppt/slideMasters/slideMaster1.xml', "#{ct}.slideMaster+xml"],
              ['/ppt/slideLayouts/slideLayout1.xml', "#{ct}.slideLayout+xml"], ['/ppt/theme/theme1.xml', 'application/vnd.openxmlformats-officedocument.theme+xml'],
              ['/ppt/presProps.xml', "#{ct}.presProps+xml"], ['/ppt/viewProps.xml', "#{ct}.viewProps+xml"], ['/ppt/tableStyles.xml', "#{ct}.tableStyles+xml"],
              ['/docProps/core.xml', 'application/vnd.openxmlformats-package.core-properties+xml'],
              ['/docProps/app.xml', 'application/vnd.openxmlformats-officedocument.extended-properties+xml']] +
             @slides.map { |s| ["/ppt/slides/slide#{s.index}.xml", "#{ct}.slide+xml"] }
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">) +
        %(<Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>) +
        %(<Default Extension="png" ContentType="image/png"/><Default Extension="jpeg" ContentType="image/jpeg"/><Default Extension="jpg" ContentType="image/jpeg"/>) +
        over.map { |part, type| %(<Override PartName="#{part}" ContentType="#{type}"/>) }.join + '</Types>'
    end

    def root_rels
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">) +
        %(<Relationship Id="rId1" Type="#{REL}/officeDocument" Target="ppt/presentation.xml"/>) +
        %(<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>) +
        %(<Relationship Id="rId3" Type="#{REL}/extended-properties" Target="docProps/app.xml"/></Relationships>)
    end

    def app_xml
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" ) +
        %(xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>PMS</Application><Slides>#{@slides.size}</Slides></Properties>)
    end

    def core_xml
      now = Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" ) +
        %(xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">) +
        %(<dc:title>#{self.class.esc(@title)}</dc:title><dc:creator>#{self.class.esc(@author)}</dc:creator><cp:lastModifiedBy>#{self.class.esc(@author)}</cp:lastModifiedBy>) +
        %(<dcterms:created xsi:type="dcterms:W3CDTF">#{now}</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">#{now}</dcterms:modified></cp:coreProperties>)
    end

    def presentation_xml
      ids = @slides.map { |s| %(<p:sldId id="#{255 + s.index}" r:id="rId#{s.index + 1}"/>) }.join
      File.read(File.join(BASE, 'presentation.xml'), encoding: 'UTF-8').sub('{{SLDIDS}}', "<p:sldIdLst>#{ids}</p:sldIdLst>")
    end

    def presentation_rels
      n = @slides.size
      list = [['rId1', 'slideMaster', 'slideMasters/slideMaster1.xml']] + @slides.map { |s| ["rId#{s.index + 1}", 'slide', "slides/slide#{s.index}.xml"] } +
             [["rId#{n + 2}", 'presProps', 'presProps.xml'], ["rId#{n + 3}", 'viewProps', 'viewProps.xml'], ["rId#{n + 4}", 'theme', 'theme/theme1.xml'],
              ["rId#{n + 5}", 'tableStyles', 'tableStyles.xml']]
      rels(list)
    end

    # 슬라이드 한 장
    class Slide
      attr_reader :index, :media_rels

      def initialize(deck, index)
        @deck = deck
        @index = index
        @shapes = []
        @media_rels = []
        @id = 1
      end

      def next_id
        @id += 1
      end

      def xfrm(x, y, w, h, tag = 'a:xfrm')
        %(<#{tag}><a:off x="#{Pptx.emu(x)}" y="#{Pptx.emu(y)}"/><a:ext cx="#{Pptx.emu(w)}" cy="#{Pptx.emu(h)}"/></#{tag}>)
      end

      def fill_xml(color)
        color ? %(<a:solidFill><a:srgbClr val="#{color}"/></a:solidFill>) : '<a:noFill/>'
      end

      def line_xml(color, width = 0.75)
        color ? %(<a:ln w="#{(width * 12_700).round}"><a:solidFill><a:srgbClr val="#{color}"/></a:solidFill></a:ln>) : '<a:ln><a:noFill/></a:ln>'
      end

      # 글자 묶음: 문자열(줄바꿈 = 문단) 또는 [{ text:, bold:, color:, size: }…] (한 문단 안 여러 조각)
      def paragraphs(content, size:, bold:, color:, align:)
        paras = content.is_a?(Array) ? [content] : content.to_s.split("\n", -1).map { |line| [{ text: line }] }
        paras = [[{ text: '' }]] if paras.empty? # 빈 글상자도 문단 하나는 있어야 함 (PowerPoint 규칙)
        paras.map do |runs|
          body = runs.map do |r|
            sz = ((r[:size] || size) * 100).round
            b = (r.key?(:bold) ? r[:bold] : bold) ? ' b="1"' : ''
            %(<a:r><a:rPr lang="ko-KR" altLang="en-US" sz="#{sz}"#{b} dirty="0">#{fill_xml(r[:color] || color)}<a:latin typeface="#{FONT}"/><a:ea typeface="#{FONT}"/></a:rPr><a:t>#{Pptx.esc(r[:text])}</a:t></a:r>)
          end.join
          %(<a:p><a:pPr algn="#{align}"/>#{body}<a:endParaRPr lang="ko-KR" altLang="en-US" sz="#{(size * 100).round}" dirty="0"><a:latin typeface="#{FONT}"/><a:ea typeface="#{FONT}"/></a:endParaRPr></a:p>)
        end.join
      end

      # 글상자 (fill·line 을 주면 칸, inset 은 안쪽 여백 인치)
      def text(x, y, w, h, content, size: 12, bold: false, color: '1E2124', align: 'l', anchor: 't', fill: nil, line: nil, inset: 0.05, name: nil)
        id = next_id
        ins = Pptx.emu(inset)
        @shapes << %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="#{Pptx.esc(name || "Text #{id}")}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>) +
                   %(<p:spPr>#{xfrm(x, y, w, h)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>#{fill_xml(fill)}#{line_xml(line)}</p:spPr>) +
                   %(<p:txBody><a:bodyPr wrap="square" lIns="#{ins}" tIns="#{ins}" rIns="#{ins}" bIns="#{ins}" rtlCol="0" anchor="#{anchor}"><a:noAutofit/></a:bodyPr><a:lstStyle/>) +
                   paragraphs(content, size: size, bold: bold, color: color, align: align) + '</p:txBody></p:sp>'
      end

      # 사각형 (글자 없이)
      def rect(x, y, w, h, fill: nil, line: nil, name: nil)
        id = next_id
        @shapes << %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="#{Pptx.esc(name || "Rect #{id}")}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>) +
                   %(<p:spPr>#{xfrm(x, y, w, h)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>#{fill_xml(fill)}#{line_xml(line)}</p:spPr></p:sp>)
      end

      # 그림 — crop: { t:, b:, l:, r: } (1/1000 %, 예: 50_000 = 50%)
      def image(data, ext, x, y, w, h, crop: nil, border: nil, alt: '')
        id = next_id
        rid = "rId#{@media_rels.size + 2}"
        name = @deck.add_media(data, ext)
        @media_rels << [rid, 'image', "../media/#{name}"]
        src = crop ? %(<a:srcRect#{%i(l t r b).map { |k| crop[k].to_i.positive? ? %( #{k}="#{crop[k].to_i}") : '' }.join}/>) : ''
        @shapes << %(<p:pic><p:nvPicPr><p:cNvPr id="#{id}" name="Picture #{id}" descr="#{Pptx.esc(alt)}"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>) +
                   %(<p:blipFill><a:blip r:embed="#{rid}"/>#{src}<a:stretch><a:fillRect/></a:stretch></p:blipFill>) +
                   %(<p:spPr>#{xfrm(x, y, w, h)}<a:prstGeom prst="rect"><a:avLst/></a:prstGeom>#{border ? line_xml(border) : ''}</p:spPr></p:pic>)
      end

      # 표 — rows: [[셀…]…], 셀은 문자열 또는 { text:, bold:, fill:, color:, align:, size: }
      def table(x, y, widths, rows, row_h: 0.32, size: 10, border: 'B1B8BE', name: nil)
        id = next_id
        grid = widths.map { |w| %(<a:gridCol w="#{Pptx.emu(w)}"/>) }.join
        ln = ->(tag) { %(<a:#{tag} w="9525"><a:solidFill><a:srgbClr val="#{border}"/></a:solidFill></a:#{tag}>) }
        trs = rows.map do |row|
          tcs = row.map do |cell|
            c = cell.is_a?(Hash) ? cell : { text: cell }
            body = paragraphs(c[:text].to_s, size: c[:size] || size, bold: c[:bold], color: c[:color] || '1E2124', align: c[:align] || 'l')
            m = Pptx.emu(0.06)
            %(<a:tc><a:txBody><a:bodyPr/><a:lstStyle/>#{body}</a:txBody><a:tcPr marL="#{m}" marR="#{m}" marT="#{Pptx.emu(0.03)}" marB="#{Pptx.emu(0.03)}" anchor="ctr">) +
              ln.('lnL') + ln.('lnR') + ln.('lnT') + ln.('lnB') + fill_xml(c[:fill]) + '</a:tcPr></a:tc>'
          end.join
          %(<a:tr h="#{Pptx.emu(row_h)}">#{tcs}</a:tr>)
        end.join
        @shapes << %(<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="#{id}" name="#{Pptx.esc(name || "Table #{id}")}"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>) +
                   xfrm(x, y, widths.sum, row_h * rows.size, 'p:xfrm') +
                   %(<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1" bandRow="0"/><a:tblGrid>#{grid}</a:tblGrid>#{trs}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>)
      end

      def to_xml
        %(<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<p:sld #{NS}><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>) +
          %(<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>) +
          @shapes.join + '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>'
      end
    end
  end
end
