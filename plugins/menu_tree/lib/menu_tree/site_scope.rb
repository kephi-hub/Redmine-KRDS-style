# 메뉴 구조도 · 시스템 권한 화면의 사이트 선택 (주소 ?site=<id>|all, 고른 값은 세션에 기억)
module MenuTree
  module SiteScope
    private

    # @sites: 프로젝트 사이트 목록, @site: 고른 사이트(nil 이면 사이트 없음 또는 "전체")
    # allow_all: "전체"를 고를 수 있는 화면(구조도·현황·권한 매트릭스). 표 편집 화면은 사이트 하나씩
    def load_sites(allow_all: false)
      @sites = MenuSite.where(project_id: @project.id).sorted.to_a
      @site = nil
      @site_all = false
      return if @sites.empty?
      store = (session[:menu_site] ||= {})
      key = @project.id.to_s
      store[key] = params[:site].to_s if params[:site].present?
      # 다른 화면에서 메뉴 링크(?focus=)로 들어오면 그 메뉴의 사이트로
      if params[:site].blank? && params[:focus].present? && (m = MenuItem.find_by(id: params[:focus].to_i, project_id: @project.id))&.menu_site_id
        store[key] = m.menu_site_id.to_s
      end
      want = store[key].to_s
      if want == 'all' && allow_all
        @site_all = true
      else
        @site = @sites.find { |s| s.id.to_s == want } || @sites.first
      end
    end

    # MenuItem.ordered 에 넘길 사이트 id (전체·사이트 없음이면 nil)
    def site_filter
      @site&.id
    end
  end
end
