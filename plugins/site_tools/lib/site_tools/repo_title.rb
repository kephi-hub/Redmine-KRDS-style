# 저장소 화면 브라우저 제목(<title>): Redmine 이 경로를 "/trunk" 처럼 앞에 / 를 붙여 넣어
# 저장소 첫 화면이 "/ - 저장소 - 프로젝트 - PMS" 로 나옴 → 앞의 / 를 떼고 루트(/)는 빼서 "저장소 - 프로젝트 - PMS"
module SiteTools
  module RepoTitle
    def html_title(*args)
      if args.any? && controller_name == 'repositories'
        args = args.map { |a| a.is_a?(String) && a.start_with?('/') ? a.sub(%r{\A/+}, '') : a }.reject(&:blank?)
        return if args.empty?   # 빈 채로 넘기면 제목을 돌려주는 동작이 되므로 그냥 끝냄
      end
      super(*args)
    end
  end
end
