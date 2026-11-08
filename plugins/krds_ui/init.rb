# Redmine 화면 보조 플러그인 — KRDS 테마(krds)용 마크업 덮어쓰기
# app/views/ 의 파일이 Redmine 기본 화면보다 우선 적용됨 (플러그인 view 경로가 앞에 붙음)
# 덮어쓴 화면 (Redmine 업그레이드 시 원본 변경 여부를 비교할 것)
# - documents/show.html.erb, index.html.erb, _document.html.erb : 문서 상세·목록 (Redmine 6.1.6 원본 기준)
# - documents/_form.html.erb : 편집 화면에도 첨부 추가·삭제 표시 (저장 처리: DocumentAttachmentsPatch)
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

Redmine::Plugin.register :krds_ui do
  name 'KRDS UI'
  author 'kephi-hub'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  description 'KRDS 테마용 화면 마크업 (문서 상세·목록), 문서 편집 첨부 추가·삭제, 번역 보충, 한글 아바타 이니셜'
  version '1.2.0'
end
