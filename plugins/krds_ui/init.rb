# Redmine 화면 보조 플러그인 — KRDS 테마(krds)용 마크업 덮어쓰기
# app/views/ 의 파일이 Redmine 기본 화면보다 우선 적용됨 (플러그인 view 경로가 앞에 붙음)
# 덮어쓴 화면 (Redmine 업그레이드 시 원본 변경 여부를 비교할 것)
# - documents/show.html.erb, index.html.erb, _document.html.erb : 문서 상세·목록 (Redmine 6.1.6 원본 기준)
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
end
User.prepend(KrdsUi::UserInitialsPatch) unless User.ancestors.include?(KrdsUi::UserInitialsPatch)

Redmine::Plugin.register :krds_ui do
  name 'KRDS UI'
  author 'kephi-hub'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  description 'KRDS 테마용 화면 마크업 (문서 상세·목록), 번역 보충, 한글 아바타 이니셜'
  version '1.1.0'
end
