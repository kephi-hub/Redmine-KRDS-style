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

/* 프로젝트 메뉴 대분류: 지금 대분류의 메뉴 줄(.nav_sub)을 머리글 바로 아래로 (krds_ui MenuGroups) */
$(function() {
  var $sub = $('#main-menu > .nav_sub');
  if ($sub.length) $sub.insertAfter('#header');
});

/* 프로젝트 메뉴 대분류 펼침 패널 (KRDS 메인 메뉴형): 데스크톱에서 대분류를 누르면 머리글 아래 전체 너비 패널,
 * 다시 누르기·닫기 버튼·Esc·바깥 누르기로 닫힘, aria-expanded 로 상태 표시. 모바일은 오른쪽 메뉴 패널 그대로 */
$(function() {
  var $panels = $('.gnb_panel');
  if (!$panels.length) return;
  var $layer = $('<div class="gnb_layer"></div>').insertAfter('#header');
  $panels.appendTo($layer);
  function desktop() { return window.matchMedia('(min-width:900px)').matches; }
  function close(focus) {
    var $t = $('#main-menu a.nav_grp[aria-expanded="true"]');
    $t.attr('aria-expanded', 'false');
    $layer.find('.gnb_panel').prop('hidden', true);
    if (focus && $t.length) $t.trigger('focus');
  }
  $('#main-menu').on('click', 'a.nav_grp[aria-controls]', function(e) {
    if (!desktop()) return;
    e.preventDefault();
    var $t = $(this), open = $t.attr('aria-expanded') === 'true';
    close(false);
    if (open) return;
    $t.attr('aria-expanded', 'true');
    $('#' + $t.attr('aria-controls')).prop('hidden', false);
  });
  $layer.on('click', '.gnb_close', function() { close(true); });
  $(document).on('keydown', function(e) { if (e.key === 'Escape') close(true); });
  $(document).on('click', function(e) { if (!$(e.target).closest('#main-menu, .gnb_layer').length) close(false); });
});
