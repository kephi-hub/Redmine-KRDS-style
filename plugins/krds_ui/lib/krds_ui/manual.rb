# 초기화면 사용 매뉴얼 — plugins/krds_ui/manual/*.md (파일 이름 순서 = 탭 순서)
# 파일 맨 위 머리말(--- key/title/icon/summary ---) + 본문(CommonMark).
# 본문 ### 는 탭 안 큰 절(목차에 나옴), #### 는 작은 절. 표는 가로 스크롤 상자로 감쌈.
# 파일이 바뀌면(수정 시각) 다시 그림 — 서버 재시작 없이 반영
module KrdsUi
  module Manual
    DIR = File.expand_path('../../manual', __dir__)
    Tab = Struct.new(:key, :title, :icon, :summary, :html, :toc, keyword_init: true)

    module_function

    def files
      Dir[File.join(DIR, '*.md')].sort
    end

    def tabs
      list = files
      stamp = list.map { |f| [f, File.mtime(f).to_i] }
      return @tabs if @tabs && @stamp == stamp
      @stamp = stamp
      @tabs = list.map { |f| parse(f) }
    end

    def parse(file)
      raw = File.read(file, encoding: 'UTF-8')
      meta = {}
      body = raw
      if raw.start_with?("---\n")
        head, body = raw[4..].split("\n---\n", 2)
        head.to_s.each_line { |l| k, v = l.split(':', 2); meta[k.strip] = v.to_s.strip if k && v }
      end
      key = meta['key'].presence || File.basename(file, '.md').sub(/\A\d+_/, '')
      html, toc = render(key, body.to_s)
      Tab.new(key: key, title: meta['title'] || key, icon: meta['icon'] || 'help', summary: meta['summary'], html: html, toc: toc)
    end

    # 본문 → [HTML, [[id, 제목]]] — 탭 제목이 h3 이므로 본문 제목은 한 단계 내림 (### → h4, #### → h5)
    def render(key, text)
      html = Redmine::WikiFormatting.to_html('common_mark', text)
      doc = Nokogiri::HTML::DocumentFragment.parse(html)
      doc.css('h4').each { |h| h.name = 'h5' }
      toc = []
      doc.css('h3').each_with_index do |h, i|
        h.name = 'h4'
        h['id'] = "man_#{key}_#{i + 1}"
        h['class'] = 'man_sec'
        toc << [h['id'], h.text.strip]
      end
      doc.css('table').each { |t| t.wrap('<div class="man_tbl" tabindex="0"></div>') }
      doc.css('pre').each { |pr| pr['tabindex'] = '0' }
      doc.css('blockquote').each { |b| b['class'] = 'man_note' }
      doc.css('a[href^="http"]').each { |a| a['target'] = '_blank'; a['rel'] = 'noopener noreferrer' }
      [doc.to_html.html_safe, toc]
    end
  end
end
