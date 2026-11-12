# Redmine 화면 보조 플러그인 — KRDS 테마(krds)용 마크업 덮어쓰기
# app/views/ 의 파일이 Redmine 기본 화면보다 우선 적용됨 (플러그인 view 경로가 앞에 붙음)
# 덮어쓴 화면 (Redmine 업그레이드 시 원본 변경 여부를 비교할 것)
# - documents/show.html.erb, index.html.erb, _document.html.erb : 문서 상세·목록 (Redmine 6.1.6 원본 기준, 목록 데이터: DocumentListPatch)
# - news/index.html.erb, files/index.html.erb : 목록 위 제목(파일명) 검색줄 (뉴스 검색 처리: NewsSearchPatch)
# - boards/index.html.erb, boards/show.html.erb, messages/show.html.erb, new.html.erb, edit.html.erb : 게시판 목록·글 목록·상세(문서 화면 형식), 등록·수정 취소 버튼
# - attachments/other.html.erb : 첨부 상세에서 PDF 미리보기(브라우저 PDF 보기), 그 외 형식은 원본과 같음
# - krds/_title_search.html.erb : 문서·뉴스·파일 공통 검색칸 (새 파일, 원본 없음)
# - documents/_form.html.erb : 편집 화면에도 첨부 추가·삭제 표시 (저장 처리: DocumentAttachmentsPatch)
# - activities/_activities.html.erb : 작업내역 시간을 오전/오후 12시간제로 표시
# - projects/_form.html.erb : 프로젝트 정보(새 프로젝트·설정)의 모듈 선택을 대분류 카드로 (krds/_project_modules, 원본 6.1.6 기준)
# - welcome/index.html.erb : 초기화면 — 안내문 + 바로 가기 + 새소식 + 탭 사용 매뉴얼(manual/*.md, KrdsUi::Manual)
# config/locales/ko.yml : core 한국어 번역 누락분 보충
# lib/krds_ui/xlsx.rb · xlsx_reader.rb : 엑셀 쓰기·읽기 공통 (rubyzip·nokogiri, 추가 gem 없음)
# assets/javascripts/mermaid*.js : Mermaid 11.4.1(MIT) 포함 — 본문 ```mermaid 그림, DB ERD·메뉴 구조도 공통 (KrdsUi::MermaidHook)
# 메인 메뉴 : KrdsUi::MenuGroups (lib/krds_ui/menu_groups.rb) — KRDS 메인 메뉴 2뎁스(PC 펼침 패널, 모바일 세로 탭 레이어)
# User#initials : 한글 이름이면 아바타에 이름(firstname) 두 글자 표시 (강윤아 → 윤아)

module KrdsUi
  module UserInitialsPatch
    def initials(formatter = nil)
      fn = firstname.to_s.strip
      return fn[0, 2] if fn.match?(/\p{Hangul}/)
      super
    end
  end

  # 문서 목록 — 범주별 영역 없이 한 목록으로 표시(범주는 제목 위 배지), 범주 검색조건 추가, 기본 정렬은 최근 순
  module DocumentListPatch
    def index
      @sort_by = %w(category date title author).include?(params[:sort_by]) ? params[:sort_by] : 'date'
      documents = @project.documents.includes(:attachments, :category).to_a
      @categories = (DocumentCategory.active.to_a | documents.map(&:category)).sort
      @category = @categories.detect {|c| c.id == params[:category_id].to_i}
      @q = params[:q].to_s.strip.presence
      documents.select! {|d| d.category == @category} if @category
      documents.select! {|d| d.title.downcase.include?(@q.downcase)} if @q
      @documents = sort_documents(documents)
      @document = @project.documents.build
      render :layout => false if request.xhr?
    end

    private

    # 정렬 기준이 같으면 최근 순 유지. 작성자 순은 원본처럼 마지막 첨부의 작성자 기준이며, 첨부 없는 문서는 뒤로
    def sort_documents(documents)
      documents.sort_by {|d| d.updated_on}.reverse.sort_by.with_index do |d, i|
        key =
          case @sort_by
          when 'category' then d.category.position
          when 'title' then d.title.downcase
          when 'author' then (a = d.attachments.last) ? [0, a.author.to_s] : [1, '']
          else 0
          end
        [key, i]
      end
    end
  end

  # 뉴스 목록 제목 검색 — 검색어가 없거나 API·Atom 요청이면 원본 그대로
  module NewsSearchPatch
    def index
      @q = params[:q].to_s.strip.presence
      return super if @q.nil? || params[:format].present?

      scope = (@project ? @project.news.visible : News.visible).
                where(Redmine::Database.like("#{News.table_name}.title", '?'), "%#{News.sanitize_sql_like(@q)}%")
      @limit = 10
      @news_count = scope.count
      @news_pages = Redmine::Pagination::Paginator.new @news_count, @limit, params['page']
      @offset = @news_pages.offset
      @newss = scope.includes([:author, :project]).order("#{News.table_name}.created_on DESC").limit(@limit).offset(@offset).to_a
      @news = News.new
      render :layout => false if request.xhr?
    end
  end

  # 문서 편집 저장 때 첨부 추가·삭제 — 추가는 편집 권한(원본 add_attachment 와 동일), 삭제는 문서 삭제 권한(원본 첨부 삭제와 동일)
  # 웹 접근성: 글자 아바타(role=img)에 사용자 이름을 대체 텍스트로 (KWCAG 5.1.1)
  module AvatarNamePatch
    def initials_avatar_tag(user, options)
      tag = super
      name = user.respond_to?(:name) ? user.name.to_s : ''
      return tag if name.empty? || tag.to_s.include?('aria-label=')
      tag.to_s.sub('<span ', "<span aria-label=\"#{ERB::Util.html_escape(name)}\" ").html_safe
    end
  end

  module DocumentAttachmentsPatch
    def update
      before_ids = @document.attachments.pluck(:id)
      @document.save_attachments(params[:attachments])
      super
      return if @document.errors.any?

      render_attachment_warning_if_needed(@document)
      ids = Array(params[:deleted_attachment_ids]).map(&:to_i)
      @document.attachments.where(:id => ids).destroy_all if ids.any? && @document.attachments_deletable?
      added = @document.attachments.where.not(:id => before_ids).to_a
      Mailer.deliver_attachments_added(added) if added.any? && Setting.notified_events.include?('document_added')
    end
  end
end
User.prepend(KrdsUi::UserInitialsPatch) unless User.ancestors.include?(KrdsUi::UserInitialsPatch)
AvatarsHelper.prepend(KrdsUi::AvatarNamePatch) unless AvatarsHelper.ancestors.include?(KrdsUi::AvatarNamePatch)
DocumentsController.prepend(KrdsUi::DocumentAttachmentsPatch) unless DocumentsController.ancestors.include?(KrdsUi::DocumentAttachmentsPatch)
DocumentsController.prepend(KrdsUi::DocumentListPatch) unless DocumentsController.ancestors.include?(KrdsUi::DocumentListPatch)
NewsController.prepend(KrdsUi::NewsSearchPatch) unless NewsController.ancestors.include?(KrdsUi::NewsSearchPatch)

require_relative 'lib/krds_ui/xlsx'
require_relative 'lib/krds_ui/xlsx_reader'
require_relative 'lib/krds_ui/pptx'
require_relative 'lib/krds_ui/menu_groups'
require_relative 'lib/krds_ui/manual'
# 메인 메뉴: KRDS 메인 메뉴 2뎁스 형태(PC 펼침 패널 · 모바일 세로 탭), 프로젝트 메뉴는 대분류 아래 2뎁스
Redmine::MenuManager::MenuHelper.prepend(KrdsUi::MenuHelperPatch) unless Redmine::MenuManager::MenuHelper.ancestors.include?(KrdsUi::MenuHelperPatch)

# Mermaid 공통: 본문 ```mermaid 그림, ERD·메뉴 구조도 그리기·저장 (assets/javascripts/mermaid_loader.js)
module KrdsUi
  class MermaidHook < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      v = context[:controller].view_context
      (%(<script>window.KRDS_MERMAID_SRC = #{v.javascript_path('plugin_assets/krds_ui/mermaid.min').to_json};</script>\n) +
        %(<script src="#{ERB::Util.h(v.javascript_path('plugin_assets/krds_ui/mermaid_loader'))}" defer></script>)).html_safe
    end
  end
end

Redmine::Plugin.register :krds_ui do
  name 'KRDS UI'
  author 'kephi-hub'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  description 'Mermaid(본문 그림·ERD·메뉴 구조도), KRDS 테마용 화면 마크업 (문서·게시판 목록·상세), 문서 범주 검색조건, 문서·뉴스·파일 제목 검색, 문서 편집 첨부 추가·삭제, 번역 보충, 한글 아바타 이니셜'
  version '1.7.0'
end
