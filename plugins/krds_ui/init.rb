# Redmine 화면 보조 플러그인 — KRDS 테마(krds)용 마크업 덮어쓰기
# app/views/ 의 파일이 Redmine 기본 화면보다 우선 적용됨 (플러그인 view 경로가 앞에 붙음)
# 덮어쓴 화면 (Redmine 업그레이드 시 원본 변경 여부를 비교할 것)
# - documents/show.html.erb, index.html.erb, _document.html.erb : 문서 상세·목록 (Redmine 6.1.6 원본 기준, 목록 데이터: DocumentListPatch)
# - news/index.html.erb, files/index.html.erb : 목록 위 제목(파일명) 검색줄 (뉴스 검색 처리: NewsSearchPatch)
# - krds/_title_search.html.erb : 문서·뉴스·파일 공통 검색칸 (새 파일, 원본 없음)
# - documents/_form.html.erb : 편집 화면에도 첨부 추가·삭제 표시 (저장 처리: DocumentAttachmentsPatch)
# - activities/_activities.html.erb : 작업내역 시간을 오전/오후 12시간제로 표시
# config/locales/ko.yml : core 한국어 번역 누락분 보충
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
DocumentsController.prepend(KrdsUi::DocumentAttachmentsPatch) unless DocumentsController.ancestors.include?(KrdsUi::DocumentAttachmentsPatch)
DocumentsController.prepend(KrdsUi::DocumentListPatch) unless DocumentsController.ancestors.include?(KrdsUi::DocumentListPatch)
NewsController.prepend(KrdsUi::NewsSearchPatch) unless NewsController.ancestors.include?(KrdsUi::NewsSearchPatch)

Redmine::Plugin.register :krds_ui do
  name 'KRDS UI'
  author 'kephi-hub'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  description 'KRDS 테마용 화면 마크업 (문서 상세·목록), 문서 범주 검색조건, 문서·뉴스·파일 제목 검색, 문서 편집 첨부 추가·삭제, 번역 보충, 한글 아바타 이니셜'
  version '1.4.0'
end
