# 자동 생성 산출물 — 시스템 데이터로 최신 엑셀을 만듦. generate 는 [[파일 이름, 데이터], …] (DB 별·회차별로 여러 개일 수 있음)
# 모듈이 꺼져 있거나 플러그인이 없으면 available? 가 false. 만들다 실패하면 같은 이름의 .txt 에 이유를 넣음
module PmKit
  module AutoDocs
    module_function

    def mod?(project, name)
      project.module_enabled?(name)
    end

    # 화면 설계서: 화면마다 최신 PC(·모바일) 캡처 PNG + 화면목록.xlsx — 사이트·1뎁스 폴더
    def screen_captures(p)
      ordered = MenuItem.ordered(p)
      index = ordered.to_h { |m, _| [m.id, m] }
      screens = MenuItem.screens(ordered)
      caps = MenuCapture.ok.where(menu_item_id: screens.map(&:id)).order(captured_at: :desc).to_a.group_by { |c| [c.menu_item_id, c.kind] }.transform_values(&:first)
      clean = ->(t) { t.to_s.gsub(%r{[\\/:*?"<>|]+}, '_').strip.truncate(60, omission: '') }
      files = []
      rows = screens.each_with_index.map do |m, i|
        root = m.parent_id ? (x = m; x = index[x.parent_id] while x.parent_id && index[x.parent_id]; x) : m
        folder = [m.site_label, root.name].compact.map(&clean).join('/')
        names = %w(pc mobile).filter_map do |k|
          c = caps[[m.id, k]]
          next unless c&.path && File.file?(c.path)
          name = "화면설계서/#{folder}/#{format('%03d', i + 1)}_#{clean.(m.screen_id || m.name)}#{'_모바일' if k == 'mobile'}.png"
          files << [name, File.binread(c.path)]
          name
        end
        pc = caps[[m.id, 'pc']]
        [i + 1, m.site_label, m.screen_id, m.path(index, site: false), m.url, MenuScreenType.labels(m.project_id)[m.screen_type], m.in_menu? ? 'Y' : 'N',
         pc&.captured_at&.strftime('%Y-%m-%d %H:%M'), names.join("\n").presence || '캡처 없음']
      end
      list = KrdsUi::Xlsx.build([{ name: '화면 목록', header: %w(번호 사이트 화면\ ID 메뉴\ 경로 URL 화면\ 유형 메뉴\ 노출 캡처\ 일시 파일), rows: rows,
                                   widths: [6, 14, 16, 40, 40, 10, 8, 16, 60] }])
      [["화면설계서/화면목록_#{today}.xlsx", list]] + files
    end

    def today
      User.current.today.strftime('%Y%m%d')
    end

    KINDS = {
      'requirements' => { label: '요구사항 정의서·추적표', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_requirements) },
                          generate: lambda { |p|
                            reqs = QaRequirement.where(project_id: p.id).to_a.sort_by { |r| [QaRequirement.category_order(r.category), r.code] }
                            [["요구사항정의서_#{today}.xlsx", QaTrace::Sheet.export_requirements(p, reqs, QaTrace::Trace.build(p, reqs))]]
                          } },
      'change_requests' => { label: '변경요청 관리대장', available: ->(p) { mod?(p, :change_requests) },
                             generate: ->(p) { [["변경요청관리대장_#{today}.xlsx", PmKit::Sheet.change_requests(PmChangeRequest.where(project_id: p.id).order(:code).to_a)]] } },
      'menu_tree' => { label: '메뉴 구조도', available: ->(p) { defined?(MenuTree) && mod?(p, :menu_tree) },
                       generate: lambda { |p|
                         ordered = MenuItem.ordered(p)
                         columns = MenuColumn.where(project_id: p.id).sorted.to_a
                         header, rows, depth, has_site = MenuTree::Sheet.export(p, ordered, columns, MenuTree::Stats.build(ordered)[:own], nil)
                         widths = (has_site ? [16] : []) + Array.new(depth, 18) + [16, 30, 10, 8, 8, 6] + columns.map { 14 } + [8, 6, 8, 30]
                         [["메뉴구조도_#{today}.xlsx", KrdsUi::Xlsx.build([{ name: '메뉴 구조도', header: header, rows: rows, widths: widths }])]]
                       } },
      'sys_roles' => { label: '시스템 권한(메뉴 권한 매트릭스)', available: ->(p) { defined?(SysRole) && mod?(p, :sys_roles) },
                       generate: lambda { |p|
                         roles = SysRole.where(project_id: p.id).active.sorted.to_a
                         ordered = mod?(p, :menu_tree) ? MenuItem.ordered(p) : []
                         cells = MenuRoleAccess.where(menu_item_id: ordered.map { |m, _| m.id }, sys_role_id: roles.map(&:id)).pluck(:menu_item_id, :sys_role_id, :access).to_h { |m, r, a| [[m, r], a] }
                         [["시스템권한_#{today}.xlsx", MenuTree::Sheet.roles_book(p, ordered, roles, cells)]]
                       } },
      'glossary' => { label: '용어사전', available: ->(p) { defined?(GlossaryTerm) && mod?(p, :glossary) },
                      generate: lambda { |p|
                        rows = GlossaryTerm.for_project(p).order(:name).map { |t| [t.name, t.name_en, t.abbr, t.category, t.data_type, t.data_length, t.definition, t.note, t.project_id ? '프로젝트' : '공통'] }
                        [["용어사전_#{today}.xlsx", KrdsUi::Xlsx.build([{ name: '용어사전', header: %w(용어 영문명 약어 분류 데이터타입 길이 정의 비고 구분), rows: rows, widths: [20, 24, 16, 12, 12, 8, 40, 24, 8] }])]]
                      } },
      'table_def' => { label: '테이블 정의서 (DB 연결별)', available: ->(p) { defined?(DbManage) && mod?(p, :db_manage) },
                       generate: lambda { |p|
                         terms = DbManage::Analysis.term_map(p)
                         DbLink.where(project_id: p.id).includes(:db_server).sorted.map do |link|
                           name = "테이블정의서_#{link.name}_#{today}"
                           PmKit::AutoDocs.safely(name) { ["#{name}.xlsx", DbManage::Docs.table_definition(link.connector.snapshot(objects: true), terms)] }
                         end
                       } },
      'common_code' => { label: '공통코드 정의서 (DB 연결별)', available: ->(p) { defined?(DbManage::Codes) && mod?(p, :db_manage) },
                         generate: lambda { |p|
                           DbLink.where(project_id: p.id).includes(:db_server).sorted.select { |l| DbManage::Codes.configured?(l) }.map do |link|
                             name = "공통코드정의서_#{link.name}_#{today}"
                             PmKit::AutoDocs.safely(name) { ["#{name}.xlsx", DbManage::Codes.xlsx(DbManage::Codes.fetch(link, link.connector.snapshot))] }
                           end
                         } },
      'privacy' => { label: '개인정보 컬럼 (DB 연결별)', available: ->(p) { defined?(DbPrivacyColumn) && mod?(p, :db_manage) },
                     generate: lambda { |p|
                       DbLink.where(project_id: p.id).includes(:db_server).sorted.select { |l| DbPrivacyColumn.where(db_link_id: l.id).exists? }.map do |link|
                         name = "개인정보컬럼_#{link.name}_#{today}"
                         PmKit::AutoDocs.safely(name) do
                           snap = link.connector.snapshot
                           rows = DbManage::Privacy.rows(DbPrivacyColumn.where(db_link_id: link.id).includes(:user).to_a, snap)
                           ["#{name}.xlsx", DbManage::Docs.privacy(rows.select { |x| x[:rec].personal? })]
                         end
                       end
                     } },
      'programs' => { label: '프로그램 목록', available: ->(p) { mod?(p, :programs) },
                      generate: lambda { |p|
                        index = defined?(MenuItem) ? MenuItem.where(project_id: p.id).index_by(&:id) : {}
                        [["프로그램목록_#{today}.xlsx", PmKit::Sheet.programs(PmProgram.where(project_id: p.id).includes(:developer).sorted.to_a, index)]]
                      } },
      'test_cases' => { label: '테스트 시나리오', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_tests) },
                        generate: ->(p) { [["테스트시나리오_#{today}.xlsx", QaTrace::Sheet.export_cases(p, QaTestCase.where(project_id: p.id).sorted.to_a, QaTrace::Trace.latest_results(p))]] } },
      'test_results' => { label: '테스트 결과서 (회차별)', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_tests) },
                          generate: lambda { |p|
                            QaTestRun.where(project_id: p.id).sorted.map do |run|
                              results = run.qa_test_results.includes(:qa_test_case, :user, issue: :status).to_a.sort_by { |r| r.qa_test_case.code }
                              ["테스트결과서_#{run.name.gsub(%r{[\\/:*?"<>|\s]+}, '_')}.xlsx", QaTrace::Sheet.export_run(p, run, results)]
                            end
                          } },
      'unit_tests' => { label: '단위 테스트 결과서 (단위 회차)', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_tests) },
                        generate: ->(p) { PmKit::AutoDocs.runs(p, 'unit') } },
      'integration_tests' => { label: '통합 테스트 결과서 (통합 회차)', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_tests) },
                               generate: ->(p) { PmKit::AutoDocs.runs(p, 'integration') } },
      'acceptance_tests' => { label: '인수 테스트 결과서 (인수 회차)', available: ->(p) { defined?(QaTrace) && mod?(p, :qa_tests) },
                              generate: ->(p) { PmKit::AutoDocs.runs(p, 'acceptance') } },
      'defects' => { label: '결함 조치 내역', available: ->(p) { mod?(p, :issue_tracking) },
                     generate: ->(p) { [["결함조치내역_#{today}.xlsx", PmKit::Sheet.defects(p)]] } },
      'wbs' => { label: 'WBS(일감 · 버전)', available: ->(p) { mod?(p, :issue_tracking) },
                 generate: ->(p) { [["WBS_#{today}.xlsx", PmKit::Sheet.wbs(p)]] } },
      'erd' => { label: 'ERD (DB 연결별 .md · draw.io)', available: ->(p) { defined?(DbManage::Erd) && mod?(p, :db_manage) },
                 generate: lambda { |p|
                   DbLink.where(project_id: p.id).includes(:db_server).sorted.flat_map do |link|
                     name = "ERD_#{link.name}_#{today}"
                     begin
                       erd = DbManage::Erd.build(link.connector.snapshot, tables: nil, columns: 'all', inferred: true)
                       title = "#{p.name} · #{link.name} ERD"
                       info = "- 생성: #{PmKit::Sheet.fmt(Time.now)} · 테이블 #{erd[:tables].size} · 관계 #{erd[:relations].size}"
                       [["#{name}.md", DbManage::Erd.markdown(title, info, erd)], ["#{name}.drawio", DbManage::Erd.drawio(erd, title)]]
                     rescue StandardError => e
                       [PmKit::AutoDocs.safely(name) { raise e }]
                     end
                   end
                 } },
      'source' => { label: '소스코드 (저장소별 zip)', heavy: true,
                    available: ->(p) { defined?(SiteTools::RepoExport) && mod?(p, :repository) && p.repositories.any? && User.current.allowed_to?(:export_repository, p) },
                    generate: lambda { |p|
                      p.repositories.select { |r| SiteTools::RepoExport.supported?(r) }.map do |repo|
                        zip, name, _, _ = SiteTools::RepoExport.build(repo, '', nil)
                        [name, { path: zip }]
                      rescue StandardError => e
                        PmKit::AutoDocs.safely("소스코드_#{repo.identifier.presence || p.identifier}") { raise e }
                      end
                    } },
      'interfaces' => { label: '인터페이스 정의서', available: ->(p) { defined?(OpsKit) && mod?(p, :ops_interfaces) },
                        generate: ->(p) { [["인터페이스정의서_#{today}.xlsx", OpsKit::Sheet.interfaces(OpsInterface.where(project_id: p.id).includes(:ops_schedule).sorted.to_a)]] } },
      'schedules' => { label: '배치 정의서', available: ->(p) { defined?(OpsKit) && mod?(p, :ops_schedules) },
                       generate: ->(p) { [["배치정의서_#{today}.xlsx", OpsKit::Sheet.schedules(OpsSchedule.where(project_id: p.id).includes(:ops_asset).sorted.to_a)]] } },
      'assets' => { label: '인프라 자산 목록', available: ->(p) { defined?(OpsKit) && mod?(p, :ops_assets) },
                    generate: ->(p) { [["자산대장_#{today}.xlsx", OpsKit::Sheet.assets(OpsAsset.for_project(p).sorted.to_a, p)]] } },
      'monthly_report' => { label: '월간 운영 보고서 (지난달)', available: ->(p) { defined?(OpsKit) && mod?(p, :ops_logs) },
                            generate: lambda { |p|
                              m = User.current.today.prev_month.beginning_of_month
                              [["월간운영보고서_#{m.strftime('%Y%m')}.xlsx", OpsKit::Report.xlsx(OpsKit::Report.build(p, m))]]
                            } },
      'risks' => { label: '이슈·위험 관리대장', available: ->(p) { mod?(p, :risks) },
                   generate: ->(p) { [["이슈위험관리대장_#{today}.xlsx", PmKit::Sheet.risks(PmRisk.where(project_id: p.id).includes(:owner).order(:code).to_a)]] } },
      'meetings' => { label: '회의록 모음', available: ->(p) { mod?(p, :meetings) },
                      generate: ->(p) { [["회의록모음_#{today}.xlsx", PmKit::Sheet.meetings(PmMeeting.where(project_id: p.id).order(:held_at).to_a)]] } },
      'screen_captures' => { label: '화면 설계서 (PPT — 운영 화면 캡처)',
                             available: ->(p) { defined?(MenuTree::ScreenDoc) && mod?(p, :menu_tree) },
                             generate: lambda { |p|
                               sites = MenuSite.where(project_id: p.id).sorted.to_a
                               clean = ->(t) { t.to_s.gsub(%r{[\\/:*?"<>|\s]+}, '_') }
                               if sites.size > 1
                                 sites.map { |st| ["화면설계서_#{clean.(st.name)}_#{today}.pptx", MenuTree::ScreenDoc.build(p, site: st)] }
                               else
                                 [["화면설계서_#{today}.pptx", MenuTree::ScreenDoc.build(p, site: sites.first)]]
                               end
                             } },
      'screen_captures_png' => { label: '화면 캡처 원본 (PNG + 화면 목록)',
                                 available: ->(p) { defined?(MenuCapture) && mod?(p, :menu_tree) && MenuCapture.where(project_id: p.id).exists? },
                                 generate: ->(p) { PmKit::AutoDocs.screen_captures(p) } },
      'audits' => { label: '감리 시정조치 계획·결과', available: ->(p) { mod?(p, :audits) },
                    generate: ->(p) { [["감리시정조치_#{today}.xlsx", PmKit::Sheet.audits(PmAudit.where(project_id: p.id).includes(:owner, :pm_audit_round, :pm_deliverable).sorted.to_a)]] } },
      'staff' => { label: '투입인력 현황', available: ->(p) { mod?(p, :staff) },
                   generate: lambda { |p|
                     list = PmStaff.where(project_id: p.id).includes(:user, :replace_of).sorted.to_a
                     from = list.map(&:start_on).compact.min || User.current.today.beginning_of_year
                     to = [list.map(&:end_on).compact.max, User.current.today].compact.max
                     [["투입인력현황_#{today}.xlsx", PmKit::Sheet.staff(list, from, to)]]
                   } },
      'sec_scans' => { label: '보안약점 진단 결과 (회차별)', available: ->(p) { mod?(p, :sec_scans) },
                       generate: lambda { |p|
                         PmSecScan.where(project_id: p.id).sorted.map do |s|
                           ["보안약점진단_#{s.name.gsub(%r{[\\/:*?"<>|\s]+}, '_')}.xlsx", PmKit::Sheet.sec_scan(s, s.pm_sec_items.includes(:fixer, :pm_program).order(:kind, :file_path, :line).to_a)]
                         end
                       } },
      'pm_weekly' => { label: '주간 보고서 (지난주)', available: ->(p) { mod?(p, :pm_reports) },
                           generate: lambda { |p|
                             from, to = PmKit::Report.period('last_week')
                             [["주간보고서_#{from.strftime('%Y%m%d')}.xlsx", PmKit::Sheet.report(p, PmKit::Report.build(p, from, to))]]
                           } },
      'pm_monthly' => { label: '월간 보고서 (지난달)', available: ->(p) { mod?(p, :pm_reports) },
                            generate: lambda { |p|
                              from, to = PmKit::Report.period('last_month')
                              [["월간보고서_#{from.strftime('%Y%m')}.xlsx", PmKit::Sheet.report(p, PmKit::Report.build(p, from, to))]]
                            } }
    }.freeze

    # 테스트 결과서 — 회차 종류별 (종류 없는 회차는 "테스트 결과서(전체)" 쪽)
    def runs(project, kind)
      QaTestRun.where(project_id: project.id, kind: kind).sorted.map do |run|
        results = run.qa_test_results.includes(:qa_test_case, :user, issue: :status).to_a.sort_by { |r| r.qa_test_case.code }
        ["테스트결과서_#{run.name.gsub(%r{[\\/:*?"<>|\s]+}, '_')}.xlsx", QaTrace::Sheet.export_run(project, run, results)]
      end
    end

    def heavy?(kind)
      !!KINDS.dig(kind, :heavy)
    end

    def safely(name)
      yield
    rescue StandardError => e
      ["#{name}_생성실패.txt", "자동 생성에 실패했습니다: #{e.message.to_s.truncate(300)}\n"]
    end

    def available?(kind, project)
      k = KINDS[kind]
      !!(k && k[:available].call(project))
    rescue StandardError
      false
    end

    def generate(kind, project)
      k = KINDS[kind]
      return [] unless k && available?(kind, project)
      list = k[:generate].call(project)
      list.compact
    rescue StandardError => e
      [safely(k[:label]) { raise e }]
    end
  end
end
