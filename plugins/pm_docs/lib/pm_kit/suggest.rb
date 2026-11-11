# 소스 경로 추천 — 저장소 커밋의 변경 파일 경로 중 프로그램 ID·화면 ID·메뉴 URL 조각이 들어간 파일 (삭제된 파일 제외)
module PmKit
  module Suggest
    module_function

    COMMON = %w(list view form index main detail popup edit new save update delete search api admin user common page do jsp html).freeze
    MAX_PATHS = 50_000

    def tokens(program)
      list = [program.code]
      m = program.menu_item
      if m
        list << m.screen_id
        list += m.url.to_s.split(%r{[/?.=&]}).last(3)
      end
      list.compact.map { |t| t.to_s.strip.downcase }.select { |t| t.length >= 4 && !COMMON.include?(t) && t.match?(/[a-z]/) }.uniq
    end

    # [{ program:, tokens:, paths: }] 경로가 하나라도 있는 것만
    def run(project)
      repo_ids = project.repositories.pluck(:id)
      return [] if repo_ids.empty?
      paths = Change.joins(:changeset).where(changesets: { repository_id: repo_ids }).where.not(action: 'D').distinct.limit(MAX_PATHS).pluck(:path)
      # 폴더는 빼고 파일(확장자 있는 것)만
      paths = paths.select { |x| File.extname(x).present? }
      lower = paths.map(&:downcase)
      PmProgram.where(project_id: project.id).includes(:menu_item).sorted.limit(500).filter_map do |p|
        toks = tokens(p)
        next if toks.empty?
        have = p.paths.map(&:downcase).to_set
        found = []
        lower.each_with_index do |path, i|
          next if have.include?(path)
          found << paths[i] if toks.any? { |t| File.basename(path).include?(t) || path.include?("/#{t}/") }
          break if found.size >= 8
        end
        { program: p, tokens: toks, paths: found } if found.any?
      end
    end
  end
end
