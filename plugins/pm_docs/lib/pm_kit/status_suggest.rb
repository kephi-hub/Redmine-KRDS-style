# 프로그램 상태 제안 — 자동으로 바꾸지 않고 [상태 제안] 화면에서 골라 반영
# - 미착수인데 커밋이 있음(커밋 메시지에 프로그램 ID, 또는 바뀐 파일이 소스 경로) → 개발 중
# - 연결된 테스트 케이스(qa_trace)가 모두 최근 결과 합격(제외 빼고) → 단위테스트 완료
module PmKit
  module StatusSuggest
    module_function

    # [[프로그램, 새 상태, 이유], …]
    def run(project)
      progs = PmProgram.where(project_id: project.id).sorted.to_a
      return [] if progs.empty?
      out = []
      todo = progs.select { |p| p.status == 'todo' }
      if todo.any? && project.repositories.any?
        repo_ids = project.repositories.map(&:id)
        comments = Changeset.where(repository_id: repo_ids).pluck(:comments, :revision)
        paths = Change.joins(:changeset).where(changesets: { repository_id: repo_ids }).pluck(:path, 'changesets.revision')
        by_path = paths.group_by { |pa, _| pa.to_s.sub(%r{\A/}, '') }
        todo.each do |p|
          hit = comments.find { |c, _| c.to_s.upcase.include?(p.code.upcase) }
          reason = hit && "커밋 r#{hit[1]} 메시지에 #{p.code}"
          unless reason
            path = p.paths.map { |x| x.sub(%r{\A/}, '') }.find { |x| by_path[x] }
            reason = path && "커밋 r#{by_path[path].first[1]} 에서 #{path} 변경"
          end
          out << [p, 'dev', reason] if reason
        end
      end
      if defined?(QaTestCase) && project.module_enabled?(:qa_tests)
        cases = QaTestCase.where(project_id: project.id, pm_program_id: progs.map(&:id)).active.to_a.group_by(&:pm_program_id)
        latest = QaTrace::Trace.latest_results(project)
        progs.each do |p|
          next if p.status == 'tested' || cases[p.id].blank?
          res = cases[p.id].map { |c| latest[c.id]&.result || 'none' }.reject { |r| r == 'skip' }
          out << [p, 'tested', "테스트 케이스 #{res.size}개 모두 합격"] if res.any? && res.all? { |r| r == 'pass' }
        end
      end
      out
    end
  end
end
