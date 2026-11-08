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
