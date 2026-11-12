# 화면 캡처 — 서버의 헤드리스 크롬(ferrum)으로 운영 화면을 열어 PNG 로 저장
# 1) 설정에 로그인 정보가 있으면 로그인 주소에서 아이디·비밀번호 입력 → 로그인 버튼(없으면 Enter) → 성공 확인
# 2) 메뉴 구조도의 화면(화면 유형·화면 ID 가 있거나 말단, URL 이 있는 것)마다 주소를 열고 전체 화면 캡처 + 작은 미리보기
#    중간에 로그인 화면으로 돌아가면 한 번 다시 로그인
# 3) 직전 캡처와 내용이 다르면 "바뀜" 표시, 화면마다 최근 N 회만 남김
require 'digest'
require 'fileutils'

module MenuTree
  module Capture
    class LoginError < StandardError; end

    MOBILE = [390, 844].freeze
    HEIGHT = 900

    module_function

    def chrome_path
      [ENV['CHROME_PATH'], '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'].compact.find { |p| File.executable?(p) }
    end

    def available?
      require 'ferrum'
      chrome_path.present?
    rescue LoadError
      false
    end

    def browser(width)
      require 'ferrum'
      Ferrum::Browser.new(browser_path: chrome_path, headless: true, window_size: [width, HEIGHT], timeout: 30, process_timeout: 40,
                          pending_connection_errors: false,
                          browser_options: { 'no-sandbox' => nil, 'disable-dev-shm-usage' => nil, 'disable-gpu' => nil, 'hide-scrollbars' => nil,
                                             'lang' => 'ko-KR', 'ignore-certificate-errors' => nil, 'disable-extensions' => nil })
    end

    # 캡처 대상 화면: [메뉴, 주소] (주소를 만들 수 없는 화면은 빼고)
    def targets(cfg)
      ordered = MenuItem.ordered(cfg.project, site: cfg.menu_site_id)
      MenuItem.screens(ordered).filter_map do |m|
        next if cfg.only_active && !m.active?
        url = cfg.resolve(m.url)
        url && [m, url]
      end
    end

    def settle(b, cfg)
      b.network.wait_for_idle(duration: 0.4, timeout: 10)
    rescue StandardError
      nil
    ensure
      sleep(cfg.wait_ms / 1000.0) if cfg.wait_ms.to_i.positive?
    end

    def first_node(b, selectors)
      selectors.to_s.split(',').map(&:strip).reject(&:empty?).each do |sel|
        node = b.css(sel).find { |n| n.evaluate('this.offsetParent !== null') rescue true }
        return node if node
      end
      nil
    end

    # 로그인 — 실패하면 LoginError (로그인 화면 캡처를 debug 로 남김)
    def login(b, cfg, debug_path = nil)
      b.go_to(cfg.login_url)
      settle(b, cfg)
      user = first_node(b, cfg.user_selector.presence || MenuCaptureConfig::USER_SELECTORS)
      pass = first_node(b, cfg.pass_selector.presence || MenuCaptureConfig::PASS_SELECTORS)
      raise LoginError, "로그인 입력칸을 찾지 못했습니다 (아이디 #{user ? '찾음' : '없음'} · 비밀번호 #{pass ? '찾음' : '없음'})" unless user && pass
      [[user, cfg.username], [pass, cfg.password]].each do |node, value|
        node.focus
        node.evaluate("this.value = ''")
        node.type(value.to_s)
      end
      # 사이트 알림창(비밀번호 오류·중복 로그인 확인 등)은 자동 확인하고 메시지는 실패 이유에 씀
      dialogs = []
      b.on(:dialog) { |d| dialogs << d.message.to_s.strip; d.accept rescue nil }
      btn = cfg.submit_selector.present? ? first_node(b, cfg.submit_selector) : submit_near(b, pass)
      if btn
        # 창 밖(아래쪽)에 있는 버튼은 마우스 클릭이 안 먹으므로 화면 가운데로 옮긴 뒤 누름
        btn.evaluate("this.scrollIntoView({block: 'center'})") rescue nil
        btn.click
      else
        pass.type(:Enter)
      end
      return true if wait_login(b, cfg)
      # 그래도 로그인 화면이면 스크립트로 한 번 더 누름 (겹친 요소·마우스 이벤트를 막는 화면)
      if btn && dialogs.empty? && password_shown?(b)
        (btn.evaluate('this.click()') rescue nil)
        return true if wait_login(b, cfg)
      end
      save_png(b, debug_path, cfg, full: false) if debug_path
      why = if cfg.logout_url.present? then "로그아웃 주소(#{cfg.logout_url})로 가는 링크가 없음"
            elsif cfg.check_selector.present? then '로그인 확인 요소가 없음'
            else '비밀번호 입력칸이 남아 있음'
            end
      why += " · 사이트 알림: #{dialogs.last.truncate(100)}" if dialogs.any?
      raise LoginError, "로그인하지 못했습니다 (로그인 후 화면에 #{why}) — 아이디·비밀번호·입력칸 선택자·로그아웃 주소를 확인하세요"
    end

    # 로그인 처리(Ajax 여러 단계 → 화면 이동)가 끝날 때까지 최대 약 6초 동안 확인
    def wait_login(b, cfg)
      sleep 0.5
      settle(b, cfg)
      8.times do
        return true if (logged_in?(b, cfg) rescue false)
        sleep 0.7
        settle(b, cfg) rescue nil
      end
      false
    end

    def password_shown?(b)
      b.css('input[type=password]').any? { |n| n.evaluate('this.offsetParent !== null') rescue false }
    rescue StandardError
      false
    end

    # 로그인 버튼 찾기 (선택자를 비웠을 때) — 비밀번호 칸에서 가까운 곳부터 넓혀 가며
    # 보이는 버튼 중 글자·id·class·onclick 에 '로그인/login/signin' 이 있는 것 → 그 영역의 submit 버튼
    # (화면 위쪽 공유·메뉴 버튼이 먼저 잡히지 않게, type=button + onclick 으로 로그인하는 화면도)
    SUBMIT_JS = <<~'JS'.freeze
      function (pw) {
        const vis = e => e.offsetParent !== null && !e.disabled;
        const re = /로그인|log\s*-?in|sign\s*-?in/i;
        const said = e => re.test((e.innerText || e.value || '') + ' ' + (e.id || '') + ' ' + (e.getAttribute('class') || '') + ' ' + (e.getAttribute('onclick') || '') + ' ' + (e.getAttribute('href') || ''));
        const sel = 'button, input[type=submit], input[type=button], input[type=image], a[href], a[onclick], [role=button]';
        for (let box = pw.form || pw.parentElement; box; box = box.parentElement) {
          const all = Array.from(box.querySelectorAll(sel)).filter(vis);
          const hit = all.find(said) || all.find(e => e.matches('button[type=submit], input[type=submit]') || (e.tagName === 'BUTTON' && !e.getAttribute('type') && e.form));
          if (hit) return hit;
          if (box === document.body) break;
        }
        return null;
      }
    JS

    def submit_near(b, pass)
      pass.evaluate("(#{SUBMIT_JS.strip})(this) && (#{SUBMIT_JS.strip})(this).setAttribute('data-mc-submit', '1')")
      first_node(b, '[data-mc-submit]')
    rescue StandardError
      nil
    end

    # 로그인 여부: 로그아웃 주소 → 로그인 확인 요소 → 비밀번호 칸이 사라짐 순서로 판단
    def logged_in?(b, cfg)
      if cfg.logout_url.present?
        logout_link?(b, cfg.resolve(cfg.logout_url) || cfg.logout_url)
      elsif cfg.check_selector.present?
        first_node(b, cfg.check_selector).present?
      else
        b.css('input[type=password]').none? { |n| n.evaluate('this.offsetParent !== null') rescue true }
      end
    end

    # 화면에 로그아웃 주소로 가는 링크·폼·버튼이 있는지 — href · action · data-href · data-url 을 절대 주소로 바꿔 경로(+쿼리)로 비교,
    # onclick(location.href='…') 이나 화면 소스 안의 주소도 인정 (버튼이 아니라 글자 링크·스크립트 이동인 사이트)
    LOGOUT_JS = <<~'JS'.freeze
      (function(target) {
        var t; try { t = new URL(target, location.href); } catch (e) { return false; }
        var path = t.pathname.replace(/\/+$/, '') || '/';
        var same = function(u) { return u.host === t.host && (u.pathname.replace(/\/+$/, '') || '/') === path && (!t.search || u.search === t.search); };
        var els = document.querySelectorAll('a[href], area[href], form[action], [data-href], [data-url], [onclick]');
        for (var i = 0; i < els.length; i++) {
          var e = els[i], vals = [e.getAttribute('href'), e.getAttribute('action'), e.getAttribute('data-href'), e.getAttribute('data-url')];
          for (var j = 0; j < vals.length; j++) {
            var v = vals[j]; if (!v || /^\s*(javascript:|#)/i.test(v)) continue;
            try { if (same(new URL(v, location.href))) return true; } catch (e2) {}
          }
          var oc = e.getAttribute('onclick'); if (oc && path.length > 1 && oc.indexOf(path) >= 0) return true;
        }
        return path.length > 1 && document.documentElement.innerHTML.indexOf(path) >= 0;
      })
    JS

    def logout_link?(b, url)
      b.evaluate("#{LOGOUT_JS.strip}(#{url.to_json})") ? true : false
    rescue StandardError
      false
    end

    # 로그인 시험: { ok:, message:, image: 경로 }
    def test_login(cfg)
      return { ok: false, message: '크롬이 설치되지 않았습니다' } unless available?
      dir = MenuCapture.root.join(cfg.project_id.to_s, 'login_test')
      FileUtils.mkdir_p(dir)
      img = dir.join("cfg#{cfg.id}.png")
      b = browser(cfg.width)
      begin
        login(b, cfg, img)
        save_png(b, img, cfg, full: false)
        { ok: true, message: "로그인 성공 — 지금 주소 #{b.current_url}", image: img }
      rescue LoginError => e
        { ok: false, message: e.message, image: (img if File.file?(img)) }
      rescue StandardError => e
        { ok: false, message: "#{e.class.name.demodulize}: #{e.message.to_s.truncate(200)}" }
      ensure
        b&.quit
      end
    end

    def png_size(data)
      data[16, 8].unpack('NN') rescue [nil, nil]
    end

    def save_png(b, path, cfg, full: true)
      h = (b.evaluate('Math.max(document.documentElement.scrollHeight, document.body ? document.body.scrollHeight : 0)').to_i rescue HEIGHT)
      data = if full && h > cfg.max_height
               b.screenshot(encoding: :binary, area: { x: 0, y: 0, width: b.viewport_size.first, height: cfg.max_height })
             else
               b.screenshot(encoding: :binary, full: full)
             end
      File.binwrite(path, data)
      data
    end

    def doc_status(b)
      ex = b.network.traffic.reverse.find { |t| t.request&.type.to_s.casecmp?('document') && t.response }
      ex&.response&.status
    rescue StandardError
      nil
    end

    # 실행 — MenuCaptureRun 을 받아 끝까지 (CaptureJob · rake 에서 부름)
    def run!(run)
      cfg = run.menu_capture_config
      run.update!(status: 'running', started_at: Time.current)
      raise '크롬이 설치되지 않았습니다 (이미지 재빌드 필요)' unless available?
      list = targets(cfg)
      run.update!(total: list.size * (cfg.mobile ? 2 : 1))
      b = browser(cfg.width)
      login_path = cfg.login? ? URI.parse(cfg.login_url).path : nil
      login(b, cfg) if cfg.login?
      list.each do |menu, url|
        kinds = cfg.mobile ? %w(pc mobile) : %w(pc)
        kinds.each do |kind|
          kind == 'mobile' ? b.resize(width: MOBILE[0], height: MOBILE[1]) : b.resize(width: cfg.width, height: HEIGHT)
          shot(b, cfg, run, menu, url, kind, login_path)
        end
      end
      run.update!(status: 'done', finished_at: Time.current)
    rescue StandardError => e
      run.update!(status: 'failed', finished_at: Time.current, error: "#{e.class.name.demodulize}: #{e.message.to_s.truncate(500)}")
    ensure
      b&.quit
    end

    def shot(b, cfg, run, menu, url, kind, login_path)
      dir = MenuCapture.root.join(cfg.project_id.to_s, menu.id.to_s)
      FileUtils.mkdir_p(dir)
      stamp = "#{Time.current.strftime('%Y%m%d%H%M%S')}_#{run.id}_#{kind}"
      rec = MenuCapture.new(project_id: cfg.project_id, menu_item: menu, menu_capture_run: run, kind: kind, url: url.truncate(500), captured_at: Time.current)
      attempt = 0
      begin
        attempt += 1
        b.network.clear(:traffic) rescue nil
        b.go_to(url)
        settle(b, cfg)
        # 세션이 끊겨 로그인 화면으로 돌아가면 한 번 다시 로그인
        if login_path && attempt == 1 && URI.parse(b.current_url).path == login_path && URI.parse(url).path != login_path
          login(b, cfg)
          raise 'relogin'
        end
        rec.http_status = doc_status(b)
        rec.final_url = b.current_url.to_s.truncate(500)
        rec.title = (b.title.to_s.truncate(300) rescue nil)
        png = save_png(b, dir.join("#{stamp}.png"), cfg)
        rec.file = "#{cfg.project_id}/#{menu.id}/#{stamp}.png"
        rec.width, rec.height = png_size(png)
        rec.bytes = png.bytesize
        rec.digest = Digest::SHA1.hexdigest(png)
        thumb = b.screenshot(encoding: :binary, format: 'jpeg', quality: 70, scale: 0.3)
        File.binwrite(dir.join("#{stamp}_s.jpg"), thumb)
        rec.thumb = "#{cfg.project_id}/#{menu.id}/#{stamp}_s.jpg"
        # 웹 접근성 자동 점검 (PC 화면만, 실패해도 캡처는 그대로)
        if kind == 'pc' && cfg.a11y && rec.http_status.to_i < 400 && A11y.available?
          begin
            list = A11y.check(b)
            rec.a11y = list.to_json
            rec.a11y_count = list.size
          rescue StandardError => e
            Rails.logger.warn("[menu_capture] a11y #{menu.id}: #{e.class} #{e.message.to_s.truncate(200)}")
          end
        end
        prev = MenuCapture.ok.where(menu_item_id: menu.id, kind: kind).order(captured_at: :desc).first
        rec.changed_from_prev = prev.present? && prev.digest != rec.digest
        rec.status = rec.http_status.to_i >= 400 ? 'error' : 'ok'
        rec.error = "HTTP #{rec.http_status}" if rec.status == 'error'
      rescue RuntimeError => e
        retry if e.message == 'relogin' && attempt < 2
        rec.status = 'error'
        rec.error = e.message.to_s.truncate(500)
      rescue StandardError => e
        rec.status = 'error'
        rec.error = "#{e.class.name.demodulize}: #{e.message.to_s.truncate(400)}"
      end
      rec.save!
      run.increment!(rec.status == 'ok' ? :ok : :failed)
      run.increment!(:changed_count) if rec.changed_from_prev
      prune(menu, kind, cfg.keep)
    end

    # 화면 × 종류마다 최근 keep 개만
    def prune(menu, kind, keep)
      MenuCapture.where(menu_item_id: menu.id, kind: kind).order(captured_at: :desc).offset(keep).each(&:destroy)
    end

    # 예약 실행 (rake): 오늘 예약된 설정마다 바로 실행
    def run_scheduled(date = Date.current)
      MenuCaptureConfig.includes(:project).select { |c| c.project&.active? && c.project.module_enabled?(:menu_tree) && c.due?(date) }.map do |cfg|
        next if MenuCaptureRun.active_for(cfg.project)
        run = MenuCaptureRun.create!(project: cfg.project, menu_capture_config: cfg, status: 'queued')
        run!(run)
        run.reload
      end.compact
    end
  end
end
