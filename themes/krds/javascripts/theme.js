/* krds 테마 스크립트 (Redmine 이 <head> 에 자동 포함) */
$(function() {
  // 검색조건: 모든 화면에서 접힌 상태로 시작 (Redmine 기본은 새 검색일 때 펼침)
  $('#query_form fieldset#filters.collapsible:not(.collapsed)').each(function() {
    var legend = $(this).children('legend')[0];
    if (legend && typeof toggleFieldset === 'function') toggleFieldset(legend);
  });

  // 접혀 있어도 적용 중인 조건 수가 보이도록 제목 옆에 개수 표시
  var $legend = $('#query_form fieldset#filters > legend');
  if (!$legend.length) return;
  var $count = $('<span class="count"></span>').appendTo($legend);
  function updateCount() {
    var n = $('#filters-table .filter input[name="f[]"]:checked').length;
    $count.text(n > 0 ? n : '');
  }
  // 조건 행은 페이지의 다른 ready 핸들러(addFilter)가 만든 뒤에 셈
  setTimeout(updateCount, 0);
  $('#query_form').on('change', '#filters input[name="f[]"], #add_filter_select', function() { setTimeout(updateCount, 0); });
});

/* 하단 버튼: 폼 끝의 저장·취소 묶음을 오른쪽 정렬(.form_btns)
 * - 취소 같은 링크는 파란 테두리 버튼(.btn_line)으로 바꿔 저장 앞에 둠 (Enter 키는 그대로 첫 저장 버튼)
 * - 두 번째 이후 저장 버튼(저장 후 계속하기 등)도 테두리 버튼
 * - 검색줄·검색조건·표 안의 폼·접속정보 화면은 제외, 화면에서 직접 .form_btns 를 쓴 폼도 그대로 둠 */
$(function() {
  function isBtn(n) { return n.nodeType === 1 && $(n).is('input[type=submit], button[type=submit]'); }
  function isLink(n) { return n.nodeType === 1 && n.tagName === 'A'; }
  function isSkip(n) {
    if (n.nodeType === 3 || n.nodeType === 8) return !n.textContent.replace(/[\s|]/g, '');
    return n.nodeType === 1 && $(n).is('script, input[type=hidden]');
  }
  // parent 끝에서부터 버튼·링크(사이의 공백·구분선 포함)만 이어진 묶음
  function tailGroup(parent) {
    var nodes = [];
    for (var n = parent.lastChild; n; n = n.previousSibling) {
      if (isSkip(n) || isBtn(n) || isLink(n)) nodes.unshift(n); else break;
    }
    while (nodes.length && isSkip(nodes[0])) nodes.shift();
    return nodes.some(isBtn) ? { nodes: nodes, whole: !n } : null;
  }
  function arrange(box) {
    $(box).contents().filter(function() { return this.nodeType === 3; }).remove();
    var first = $(box).children('input[type=submit], button[type=submit]').first();
    $(box).children('a').addClass('btn_line').insertBefore(first);
    $(box).children('input[type=submit], button[type=submit]').slice(1).addClass('btn_line');
  }
  $('#content form').not('.list_search, #query_form').each(function() {
    if ($(this).find('.form_btns').length || $(this).closest('td, .pwd-form').length) return;
    var last = $(this).children().not('script, input[type=hidden]').last()[0];
    var g = last && last.tagName === 'P' ? tailGroup(last) : null;
    if (g && g.whole) { $(last).addClass('form_btns'); arrange(last); return; }
    g = tailGroup(this);
    if (!g) return;
    var box = $('<div class="form_btns"></div>').insertBefore(g.nodes[0]);
    box.append($(g.nodes).filter(function() { return isBtn(this) || isLink(this); }));
    arrange(box[0]);
  });
});

/* 목록 화면의 인라인 등록 폼(게시판 새글쓰기·새 문서·새 뉴스)이 열려 있는 동안 오른쪽 위 추가 버튼을 숨김, 취소하면 다시 표시 */
$(function() {
  var $add = $('#content>.contextual a.icon-add[onclick*="showAndScrollTo"]');
  if (!$add.length) return;
  $add.on('click', function() { $add.hide(); });
  $('#add-message, #add-document, #add-news').on('click', 'a[onclick*=".hide()"]', function() { $add.show(); });
});

/* 같은 저장 버튼이 두 개(Redmine 의 데스크톱용 .mobile-hide · 모바일용 .mobile-show)인 폼은 아래쪽 하나만 남김
 * — 하단 오른쪽 정렬 규칙(.form_btns)에 맞추고, 화면 폭과 관계없이 저장 버튼은 폼 끝에 하나 (예: 일감 유형·사용자 편집) */
$(function() {
  $('#content form').each(function() {
    var $form = $(this);
    var $bottom = $form.find('input.mobile-show[type=submit], .mobile-show > input[type=submit]');
    if (!$bottom.length) return;
    $form.find('input.mobile-hide[type=submit]').remove();
    $form.find('.mobile-hide').filter(function() {
      return $(this).find('input[type=submit]').length && !$(this).children().not('input[type=submit]').length;
    }).remove();
    $bottom.removeClass('mobile-show').closest('.mobile-show').removeClass('mobile-show');
  });
});

/* 메인 메뉴 — KRDS 메인 메뉴 2뎁스 (krds_ui MenuGroups)
 * PC: 1뎁스 버튼을 누르면(마우스오버 아님) 머리글 아래 2뎁스 패널 + 화면 어둡게. 다시 누르기·바깥·어두운 곳·Esc 로 닫힘(Esc 는 1뎁스로 초점)
 * 모바일: 메뉴 레이어를 전체 화면으로, 위에 "전체 메뉴"·닫기, 일반 메뉴를 위쪽 버튼 줄로, 프로젝트 메뉴는 왼쪽 세로 탭 + 오른쪽 2뎁스(스크롤 위치에 따라 탭 표시) */
$(function() {
  var $panels = $('.gnb_panel');
  if ($panels.length) {
    var $layer = $('<div class="gnb_layer"></div>').insertAfter('#header');
    var $dim = $('<div class="gnb_dim" hidden></div>').appendTo('body');
    $panels.appendTo($layer);
    var close = function(focus) {
      var $t = $('#main-menu .gnb_trigger[aria-expanded="true"]');
      $t.attr('aria-expanded', 'false');
      $layer.find('.gnb_panel').prop('hidden', true);
      $dim.prop('hidden', true);
      if (focus && $t.length) $t.trigger('focus');
    };
    $(document).on('click', '#main-menu .gnb_trigger[aria-controls]', function(e) {
      e.preventDefault();
      var $t = $(this), open = $t.attr('aria-expanded') === 'true';
      close(false);
      if (open) return;
      $t.attr('aria-expanded', 'true');
      $('#' + $t.attr('aria-controls')).prop('hidden', false);
      $dim.prop('hidden', false);
    });
    $dim.on('click', function() { close(false); });
    $(document).on('keydown', function(e) { if (e.key === 'Escape' && !$dim.prop('hidden')) close(true); });
    $(document).on('click', function(e) { if (!$(e.target).closest('#main-menu, .gnb_layer').length) close(false); });
    $(window).on('resize', function() { if (!window.matchMedia('(min-width:900px)').matches) close(false); });
  }

  var $fly = $('.js-flyout-menu');
  if (!$fly.length) return;
  var $head = $('<div class="mnav_head"><span>전체 메뉴</span><button type="button" class="mnav_close"></button></div>');
  $head.find('.mnav_close').attr('aria-label', '메뉴 닫기').html('&times;').on('click', function() { if (typeof closeFlyout === 'function') closeFlyout(); });
  $fly.prepend($head);
  // 일반 메뉴(초기화면·내 페이지 …)는 사용자 정보 바로 아래 버튼 줄로
  var $gen = $fly.find('.js-general-menu');
  $gen.prev('h3').hide();
  var $after = $fly.find('.flyout-menu__avatar').length ? $fly.find('.flyout-menu__avatar') : $head;
  $gen.insertAfter($after);
  var $m = $('#main-menu .mnav');
  var $pm = $fly.find('.js-project-menu');
  if (!$m.length || !$pm.length) return;
  $pm.prev('h3').hide();
  $m.prependTo($pm);
  var $tabs = $m.find('.mnav_tabs a'), $secs = $m.find('.mnav_sec');
  $tabs.on('click', function(e) {
    e.preventDefault();
    var $s = $($(this).attr('href'));
    if (!$s.length) return;
    $fly.scrollTop($fly.scrollTop() + ($s.offset().top - $fly.offset().top) - 56);
  });
  $fly.on('scroll', function() {
    var top = $fly.offset().top + 64, cur = null;
    $secs.each(function() { if ($(this).offset().top <= top + 4) cur = this.id; });
    if (!cur) cur = $secs.first().attr('id');
    $tabs.each(function() { var on = $(this).attr('href') === '#' + cur; $(this).toggleClass('on', on).attr('aria-selected', on ? 'true' : 'false'); });
  });
  // 레이어를 열면 지금 메뉴가 있는 묶음으로
  $(document).on('click', '.js-flyout-menu-toggle-button', function() {
    setTimeout(function() {
      var $cur = $m.find('.mnav_sec a.on').closest('.mnav_sec');
      if ($cur.length) $fly.scrollTop($fly.scrollTop() + ($cur.offset().top - $fly.offset().top) - 56);
    }, 50);
  });
});

/* 저장소 화면: 원본 오른쪽 버튼(통계·더보기·개정판)을 "저장소" 제목 줄(.repo_bar, site_tools 훅) 버튼 영역으로 */
$(function() {
  var $btns = $('#content > .repo_bar .repo_btns');
  if (!$btns.length) return;
  var $ctx = $('#content > .contextual').first();
  if ($ctx.length) $btns.prepend($ctx.children());
  $ctx.remove();
});
