// 프로젝트 접속정보 목록 — 손잡이(⋮⋮)를 끌어 순서 바꾸기 (마우스·터치: pointer 이벤트), 손잡이에서 위·아래 화살표로도
// 놓으면 이 쪽에 보이는 순서를 저장 (window.VK_ORDER: url · 문구)
$(function() {
  var C = window.VK_ORDER, $tb = $('#keys_table tbody');
  if (!C || !$tb.length) return;
  var live = $('<div class="vk_live" role="status" aria-live="polite"></div>').appendTo('body');
  var token = $('meta[name="csrf-token"]').attr('content');

  function rows() { return $tb.children('tr.vk_row'); }
  function ids() { return rows().map(function() { return $(this).data('key-id'); }).get(); }
  function save() {
    return fetch(C.url, { method: 'POST', credentials: 'same-origin',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token },
      body: JSON.stringify({ ids: ids() })
    }).then(function(r) {
      if (!r.ok) throw r;
      if (window.krdsToast) window.krdsToast(C.saved);
    }).catch(function() {
      (window.KrdsDialog ? window.KrdsDialog.alert(C.failed) : Promise.resolve(window.alert(C.failed)));
    });
  }
  function restripe() { rows().each(function(i) { $(this).removeClass('odd even').addClass(i % 2 ? 'even' : 'odd'); }); }
  function announce($tr) {
    live.text(C.moved.replace('%{name}', $.trim($tr.find('td.vk_name a, td.vk_name span').first().text())).replace('%{n}', rows().index($tr) + 1));
  }

  // 끌기 (행을 옮기면 포인터 캡처가 풀리므로 이동·놓기는 문서에서 받음)
  var drag = null;
  $tb.on('pointerdown', '.vk_drag', function(e) {
    if (e.button && e.button !== 0) return;
    e.preventDefault();
    var $tr = $(this).closest('tr');
    drag = { $tr: $tr, moved: false, order: ids().join() };
    $tr.addClass('on');
    $('body').addClass('vk_dragging');
  });
  $(document).on('pointermove', function(e) {
    if (!drag) return;
    var y = e.clientY, $tr = drag.$tr;
    rows().not($tr).each(function() {
      var r = this.getBoundingClientRect();
      if (y > r.top && y < r.bottom) {
        if (y < r.top + r.height / 2) $tr.insertBefore(this); else $tr.insertAfter(this);
        drag.moved = true;
        return false;
      }
    });
    // 화면 끝 가까이면 스크롤
    if (y < 60) window.scrollBy(0, -12); else if (y > window.innerHeight - 60) window.scrollBy(0, 12);
  });
  $(document).on('pointerup pointercancel', function() {
    if (!drag) return;
    var d = drag; drag = null;
    d.$tr.removeClass('on');
    $('body').removeClass('vk_dragging');
    if (d.moved && ids().join() !== d.order) { restripe(); announce(d.$tr); save(); }
  });

  // 키보드: 위·아래 화살표
  $tb.on('keydown', '.vk_drag', function(e) {
    if (e.key !== 'ArrowUp' && e.key !== 'ArrowDown') return;
    e.preventDefault();
    var $tr = $(this).closest('tr'), $to = e.key === 'ArrowUp' ? $tr.prevAll('tr.vk_row:visible').first() : $tr.nextAll('tr.vk_row:visible').first();
    if (!$to.length) return;
    if (e.key === 'ArrowUp') $tr.insertBefore($to); else $tr.insertAfter($to);
    $(this).trigger('focus');
    restripe(); announce($tr);
    clearTimeout($tb.data('t')); $tb.data('t', setTimeout(save, 500));
  });
});
