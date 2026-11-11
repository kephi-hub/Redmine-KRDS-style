/* 메뉴 구조도 엑셀형 표 — 메뉴 구조도 플러그인
   - 서버 JSON(rows, max_depth)으로 표를 그림: 1뎁스…N뎁스 칸(가장 깊은 메뉴에 맞춰 자동), 화면 ID·URL·유형·채널·대상 권한·사용·추가 칼럼·일감·진행률·비고
   - 칸을 눌러 바로 고침(Enter 저장·아래로, Tab 다음 칸, Esc 취소). 메뉴명 칸에서 Tab 들여쓰기 / Shift+Tab 내어쓰기
   - 행 ⋯ 메뉴(아래·하위 추가, 들여·내어쓰기, 위·아래, 일감, 삭제), 끌어서 옮기기, 접기·펼치기, 검색, 고른 메뉴로 일감 만들기 */
(function($) {
  'use strict';
  var C, rows = [], maxDepth = 1, byId = {}, collapsed = {}, selected = {}, editing = null, focusDone = false;
  var KEY = 'mt_collapsed_' + location.pathname;

  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function(c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  function t(k) { return C.t[k] || k; }
  function url(k, id) { return C.urls[k].replace(/\/0(\/|$)/, '/' + id + '$1'); }
  function token() { return $('meta[name="csrf-token"]').attr('content'); }
  function api(method, u, data) {
    return $.ajax({ url: u, method: method, data: data, dataType: 'json', headers: { 'X-CSRF-Token': token() } })
      .fail(function(x) { msg((x.responseJSON && x.responseJSON.message) || t('error'), true); });
  }
  function msg(text, bad) {
    var $m = $('#mt_msg'); $m.text(text).toggleClass('on', !bad).toggleClass('bad', !!bad).prop('hidden', false);
    clearTimeout(msg.timer); msg.timer = setTimeout(function() { $m.prop('hidden', true); }, bad ? 6000 : 2500);
  }
  function saveCollapsed() { try { sessionStorage.setItem(KEY, JSON.stringify(Object.keys(collapsed))); } catch (e) {} }
  try { (JSON.parse(sessionStorage.getItem(KEY) || '[]') || []).forEach(function(id) { collapsed[id] = true; }); } catch (e) {}

  function load(then) {
    return $.getJSON(C.urls.data).done(function(d) {
      rows = d.rows; maxDepth = Math.max(1, d.max_depth); byId = {};
      rows.forEach(function(r) { byId[r.id] = r; });
      Object.keys(selected).forEach(function(id) { if (!byId[id]) delete selected[id]; });
      render(); kpi();
      if (then) then();
      if (!focusDone && C.focus && byId[C.focus]) { focusDone = true; reveal(C.focus); }
    });
  }

  // 표 칸 정의
  function columns() {
    var cols = [{ key: 'sel' }];
    if (C.canEdit) cols.push({ key: 'drag' });
    for (var d = 0; d < maxDepth; d++) cols.push({ key: 'd' + d, depth: d, label: (d + 1) + t('depth') });
    cols.push({ key: 'screen_id', edit: 'text', label: t('screen_id') });
    cols.push({ key: 'url', edit: 'text', label: t('url') });
    cols.push({ key: 'screen_type', edit: 'select', options: C.types, label: t('type') });
    cols.push({ key: 'channel', edit: 'select', options: C.channels, label: t('channel') });
    if (rows.length && rows[0].roles !== null) cols.push({ key: 'roles', label: t('roles') });
    cols.push({ key: 'active', edit: 'bool', label: t('active') });
    C.columns.forEach(function(c) {
      var opts = null;
      if (c.kind === 'list') { opts = {}; c.options.forEach(function(o) { opts[o] = o; }); }
      cols.push({ key: 'x' + c.id, edit: { text: 'text', list: 'select', bool: 'bool', date: 'date' }[c.kind], options: opts, label: c.name, extra: true });
    });
    cols.push({ key: 'issues', label: t('issues') });
    cols.push({ key: 'progress', label: t('progress') });
    cols.push({ key: 'note', edit: 'text', label: t('note') });
    if (C.canEdit) cols.push({ key: 'act' });
    return cols;
  }

  function value(r, key) { return key.charAt(0) === 'x' && key !== 'x' ? (r.extra || {})[key.slice(1)] : r[key]; }

  function visible() {
    var q = $('#mt_q').val().toLowerCase().trim(), act = $('#mt_active').val(), show = {};
    if (q || act) {
      rows.forEach(function(r) {
        var hit = (!q || [r.name, r.screen_id, r.url, r.note].join(' ').toLowerCase().indexOf(q) >= 0) &&
                  (!act || String(r.active ? 1 : 0) === act);
        if (hit) { var n = r; while (n) { show[n.id] = true; n = byId[n.parent_id]; } }
      });
      return rows.filter(function(r) { return show[r.id]; });
    }
    var hide = {};
    return rows.filter(function(r) {
      if (r.parent_id && (hide[r.parent_id] || collapsed[r.parent_id])) { hide[r.id] = true; return false; }
      return true;
    });
  }

  function cell(r, c) {
    var v = value(r, c.key), cls = [], inner = '', attrs = '';
    if (c.key === 'sel') return '<td class="mt_sel"><input type="checkbox" class="mt_ck" ' + (selected[r.id] ? 'checked' : '') + ' aria-label="' + esc(r.name) + '"></td>';
    if (c.key === 'drag') return '<td class="mt_drag" title="' + esc(t('drag')) + '"><span class="mt_handle" aria-hidden="true">⋮⋮</span></td>';
    if (c.key === 'act') return '<td class="mt_act"><button type="button" class="mt_more" aria-label="' + esc(r.name) + ' ⋯">⋯</button></td>';
    if (c.depth !== undefined) {
      if (c.depth < r.depth) return '<td class="mt_gap"></td>';
      if (c.depth > r.depth) return '<td class="mt_after"></td>';
      var tog = r.has_children ? '<button type="button" class="mt_tog" aria-expanded="' + (!collapsed[r.id]) + '" aria-label="' + esc(collapsed[r.id] ? t('expand') : t('collapse')) + '">' + (collapsed[r.id] ? '▸' : '▾') + '</button>' : '<span class="mt_leaf"></span>';
      return '<td class="mt_name' + (C.canEdit ? ' mt_ed' : '') + (r.active ? '' : ' mt_off') + '" data-key="name" tabindex="0" colspan="' + (maxDepth - r.depth) + '">' + tog + '<span class="mt_txt">' + esc(r.name) + '</span></td>';
    }
    if (c.key === 'issues') {
      var o = r.own, tr = r.tree, link = C.urls.issueList.replace('__ID__', r.id);
      if (o && o.total) inner = '<a href="' + esc(link) + '" title="' + esc((o.users || []).join(', ')) + '">' + o.total + '</a><span class="mt_dim"> / ' + t('done') + ' ' + o.closed + '</span>';
      else if (tr) inner = '<a class="mt_sum" href="' + esc(link) + '" title="' + esc(t('subtotal')) + '">Σ ' + tr.total + '</a>';
      else inner = C.canIssue ? '<a class="mt_new" href="' + esc(C.urls.newIssue.replace('__ID__', r.id)) + '">+ ' + esc(t('issue_new')) + '</a>' : '';
      return '<td class="mt_issues">' + inner + '</td>';
    }
    if (c.key === 'progress') {
      var p = (r.own && r.own.total) ? r.own : r.tree;
      if (!p) return '<td class="mt_prog"></td>';
      return '<td class="mt_prog' + ((r.own && r.own.total) ? '' : ' mt_sumcell') + '"><span class="mt_bar"><span style="width:' + p.ratio + '%"></span></span><span class="mt_pct">' + p.ratio + '%</span></td>';
    }
    if (c.key === 'roles') {
      inner = (r.roles || []).map(function(x) { return '<span class="mt_role">' + esc(x[0]) + ' <b>' + esc(x[1]) + '</b></span>'; }).join('');
      if (!inner && C.urls.matrix) inner = '<span class="mt_dim">-</span>';
      return '<td class="mt_roles">' + inner + '</td>';
    }
    if (c.edit === 'bool') {
      var on = c.key === 'active' ? !!v : !!v;
      inner = c.key === 'active' ? '<span class="mt_yn ' + (on ? 'on' : '') + '">' + (on ? t('yes') : t('no')) + '</span>' : (on ? '<span class="mt_check">✓</span>' : '');
    } else if (c.edit === 'select' && c.options) {
      inner = v ? esc(c.options[v] || v) : '';
    } else {
      inner = esc(v);
    }
    if (c.key === 'url' && v) inner = '<code>' + inner + '</code>';
    if (c.key === 'screen_id' && v) inner = '<code>' + inner + '</code>';
    cls.push('mt_c_' + c.key.replace(/^x\d+$/, 'x'));
    if (c.edit && C.canEdit) { cls.push('mt_ed'); attrs = ' tabindex="0"'; }
    return '<td class="' + cls.join(' ') + '" data-key="' + c.key + '"' + attrs + '>' + inner + '</td>';
  }

  function render() {
    // 표를 다시 그리면 편집 중이던 칸은 사라지므로 편집 상태를 풀어 둠 (빠르게 연달아 누를 때 다음 편집이 막히지 않게)
    editing = null;
    var cols = columns(), list = visible();
    var head = '<tr>' + cols.map(function(c) {
      if (c.key === 'sel') return '<th class="mt_sel"><input type="checkbox" id="mt_all" aria-label="' + esc(t('select_all')) + '"></th>';
      if (c.key === 'drag' || c.key === 'act') return '<th class="mt_' + c.key + '"></th>';
      return '<th class="' + (c.depth !== undefined ? 'mt_dh' : 'mt_h_' + c.key.replace(/^x\d+$/, 'x')) + '">' + esc(c.label) + '</th>';
    }).join('') + '</tr>';
    var body = list.length ? list.map(function(r) {
      var out = [], skip = false;
      cols.forEach(function(c) {
        if (c.depth !== undefined) {
          if (c.depth > r.depth) return;     // 메뉴명 칸이 남은 뎁스 칸을 합쳐 씀
        }
        out.push(cell(r, c));
      });
      return '<tr class="mt_row d' + Math.min(r.depth, 5) + (r.active ? '' : ' mt_unused') + '" data-id="' + r.id + '">' + out.join('') + '</tr>';
    }).join('') : '<tr><td class="mt_empty" colspan="' + cols.length + '">' + esc(t('no_rows')) + '</td></tr>';
    $('#mt_grid thead').html(head);
    $('#mt_grid tbody').html(body);
    selCount();
  }

  function kpi() {
    var parents = {}; rows.forEach(function(r) { if (r.parent_id) parents[r.parent_id] = true; });
    var leaves = rows.filter(function(r) { return !parents[r.id]; });
    var linked = leaves.filter(function(r) { return r.own && r.own.total; });
    var done = linked.filter(function(r) { return r.own.closed === r.own.total; });
    var issues = rows.reduce(function(n, r) { return n + ((r.own && r.own.total) || 0); }, 0);
    var ratio = linked.length ? Math.round(linked.reduce(function(n, r) { return n + r.own.ratio; }, 0) / linked.length) : 0;
    var items = [[t('k_menus'), rows.length], [t('k_screens'), leaves.length], [t('k_linked'), linked.length + ' / ' + leaves.length],
                 [t('k_done'), done.length], [t('k_issues'), issues], [t('k_ratio'), ratio + '%']];
    $('#mt_kpi').html(items.map(function(i) { return '<li><span>' + esc(i[0]) + '</span><strong>' + esc(i[1]) + '</strong></li>'; }).join(''));
  }

  function selCount() {
    var n = Object.keys(selected).length;
    $('#mt_sel_cnt, .mt_sel_cnt2').text(n); $('#mt_issue_btn').prop('disabled', n === 0);
  }

  function reveal(id) {
    var n = byId[id], changed = false;
    while (n && n.parent_id) { if (collapsed[n.parent_id]) { delete collapsed[n.parent_id]; changed = true; } n = byId[n.parent_id]; }
    if (changed) { saveCollapsed(); render(); }
    var $tr = $('#mt_grid tr[data-id="' + id + '"]').addClass('mt_focus');
    if ($tr.length) $tr[0].scrollIntoView({ block: 'center' });
  }

  // ---- 칸 편집 ----
  function colDef(key) { return columns().filter(function(c) { return c.key === key || (key === 'name' && c.depth !== undefined); })[0]; }

  function startEdit($td) {
    if (!C.canEdit || editing) return;
    var id = $td.closest('tr').data('id'), key = $td.data('key'), r = byId[id], c = key === 'name' ? { edit: 'text' } : colDef(key);
    if (!r || !c || !c.edit) return;
    if (c.edit === 'bool') { save(id, key, value(r, key) ? '0' : '1'); return; }
    var v = key === 'name' ? r.name : value(r, key), $in;
    if (c.edit === 'select') {
      $in = $('<select class="mt_input"><option value=""></option></select>');
      $.each(c.options || {}, function(k, label) { $in.append($('<option>').val(k).text(label)); });
      $in.val(v || '');
    } else {
      $in = $('<input class="mt_input">').attr('type', c.edit === 'date' ? 'date' : 'text').val(v || '');
      if (key === 'name') $in.attr('maxlength', 150);
    }
    editing = { id: id, key: key, $td: $td, old: v || '' };
    $td.addClass('mt_editing').data('html', $td.html()).empty().append($in);
    $in.trigger('focus'); if ($in.is('input[type=text]')) $in[0].select();
    $in.on('keydown', function(e) {
      if (e.key === 'Escape') { e.preventDefault(); cancel(); return; }
      if (e.key === 'Enter') { e.preventDefault(); finish('down'); return; }
      if (e.key === 'Tab') {
        e.preventDefault();
        if (key === 'name') finish(e.shiftKey ? 'outdent' : 'indent');
        else finish(e.shiftKey ? 'prev' : 'next');
      }
    }).on('blur', function() { setTimeout(function() { if (editing && editing.$td.is($td)) finish(null); }, 0); });
    if (c.edit === 'select' || c.edit === 'date') $in.on('change', function() { finish(null); });
  }

  function cancel() {
    if (!editing) return;
    editing.$td.removeClass('mt_editing').html(editing.$td.data('html'));
    var $td = editing.$td; editing = null; $td.trigger('focus');
  }

  function finish(next) {
    if (!editing) return;
    var e = editing, v = e.$td.find('.mt_input').val();
    editing = null;
    var after = function() { afterEdit(e.id, e.key, next); };
    if (String(v) === String(e.old)) { e.$td.removeClass('mt_editing').html(e.$td.data('html')); after(); return; }
    if (e.key === 'name' && !String(v).trim()) { e.$td.removeClass('mt_editing').html(e.$td.data('html')); return; }
    save(e.id, e.key, v, after);
  }

  function save(id, key, v, then) {
    api('PATCH', url('item', id), { field: key, value: v }).done(function() {
      var r = byId[id];
      if (key.charAt(0) === 'x' && /^x\d+$/.test(key)) { r.extra = r.extra || {}; if (v === '' || v === '0') delete r.extra[key.slice(1)]; else r.extra[key.slice(1)] = v; }
      else if (key === 'active') r.active = v === '1';
      else r[key] = v;
      // 목록·체크 칸 값은 서버 정리 결과를 다시 받음
      load(then);
    }).fail(function() { load(); });
  }

  function cellAt(id, key) { return $('#mt_grid tr[data-id="' + id + '"] td[data-key="' + key + '"]'); }

  function afterEdit(id, key, next) {
    if (next === 'indent' || next === 'outdent') { move(id, next, function() { cellAt(id, 'name').trigger('focus'); }); return; }
    var $td = cellAt(id, key);
    if (!next) { $td.trigger('focus'); return; }
    if (next === 'down') {
      var $n = $td.closest('tr').next('tr').find('td[data-key="' + key + '"]');
      ($n.length ? $n : $td).trigger('focus'); return;
    }
    var $cells = $td.closest('tr').find('td.mt_ed'), i = $cells.index($td);
    var $to = $cells.eq(next === 'next' ? i + 1 : i - 1);
    if ($to.length && (next === 'next' || i > 0)) startEdit($to); else $td.trigger('focus');
  }

  // ---- 구조 ----
  function move(id, op, then, extra) {
    api('POST', url('move', id), $.extend({ op: op }, extra || {})).done(function() { load(then); });
  }
  function add(data) {
    api('POST', C.urls.create, $.extend({ name: t('new_name') }, data)).done(function(res) {
      if (data.parent_id) { delete collapsed[data.parent_id]; saveCollapsed(); }
      load(function() { var $td = cellAt(res.id, 'name'); $td[0] && $td[0].scrollIntoView({ block: 'center' }); startEdit($td); });
    });
  }
  function remove(id) {
    var count = 0, walk = function(pid) { rows.forEach(function(r) { if (r.parent_id === pid) { count++; walk(r.id); } }); };
    walk(id);
    if (!confirm(t('delete_confirm').replace('%{name}', byId[id].name).replace('%{count}', count))) return;
    api('DELETE', url('item', id)).done(function() { delete selected[id]; load(); });
  }

  // 행 ⋯ 메뉴
  function rowMenu($btn) {
    $('.mt_pop').remove();
    var id = $btn.closest('tr').data('id'), r = byId[id];
    var items = [['add_below', function() { add({ after_id: id }); }], ['add_child', function() { add({ parent_id: id }); }],
                 ['indent', function() { move(id, 'indent'); }], ['outdent', function() { move(id, 'outdent'); }],
                 ['up', function() { move(id, 'up'); }], ['down', function() { move(id, 'down'); }],
                 ['issues_view', function() { location.href = C.urls.issueList.replace('__ID__', id); }]];
    if (C.canIssue) items.push(['issue_new', function() { location.href = C.urls.newIssue.replace('__ID__', id); }]);
    items.push(['delete', function() { remove(id); }]);
    var $p = $('<div class="mt_pop" role="menu"></div>');
    items.forEach(function(it) {
      $('<button type="button" role="menuitem">').text(t(it[0])).addClass(it[0] === 'delete' ? 'mt_danger' : '').on('click', function() { $p.remove(); it[1](); }).appendTo($p);
    });
    var o = $btn.offset();
    $p.css({ top: o.top + $btn.outerHeight() + 4, left: Math.max(8, o.left - 150) }).appendTo('body');
    $p.find('button').first().trigger('focus');
  }

  // ---- 일감 일괄 생성 ----
  function makeIssues() {
    var ids = Object.keys(selected);
    if (!ids.length) return;
    var data = $('#mt_issue_form').serializeArray();
    ids.forEach(function(id) { data.push({ name: 'ids[]', value: id }); });
    $('#mt_issue_go').prop('disabled', true);
    api('POST', C.urls.issues, $.param(data)).done(function(res) {
      hideModal($('#mt_issue_go')[0]);
      msg(res.message + (res.errors && res.errors.length ? ' — ' + res.errors.join(' / ') : ''), !res.ok);
      selected = {}; load();
    }).always(function() { $('#mt_issue_go').prop('disabled', false); });
  }

  $(function() {
    C = window.MT_CONFIG; if (!C) return;
    load();
    var $g = $('#mt_grid');
    $g.on('click', 'td.mt_ed', function(e) { if (!$(e.target).closest('.mt_tog, a, input').length) startEdit($(this)); });
    $g.on('keydown', 'td.mt_ed', function(e) {
      if (editing) return;
      if (e.key === 'Enter' || e.key === 'F2') { e.preventDefault(); startEdit($(this)); }
      else if ($(this).data('key') === 'name' && e.key === 'Tab' && C.canEdit) { e.preventDefault(); move($(this).closest('tr').data('id'), e.shiftKey ? 'outdent' : 'indent', (function(id) { return function() { cellAt(id, 'name').trigger('focus'); }; })($(this).closest('tr').data('id'))); }
      else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault();
        var key = $(this).data('key'), $tr = $(this).closest('tr')[e.key === 'ArrowDown' ? 'next' : 'prev']('tr');
        $tr.find('td[data-key="' + key + '"]').trigger('focus');
      }
    });
    $g.on('click', '.mt_tog', function() {
      var id = $(this).closest('tr').data('id');
      if (collapsed[id]) delete collapsed[id]; else collapsed[id] = true;
      saveCollapsed(); render();
    });
    $g.on('change', '.mt_ck', function() { var id = $(this).closest('tr').data('id'); if (this.checked) selected[id] = true; else delete selected[id]; selCount(); });
    $g.on('change', '#mt_all', function() { var on = this.checked; $g.find('tbody tr[data-id]').each(function() { var id = $(this).data('id'); if (on) selected[id] = true; else delete selected[id]; }); render(); });
    $g.on('click', '.mt_more', function(e) { e.stopPropagation(); rowMenu($(this)); });
    $(document).on('click', function(e) { if (!$(e.target).closest('.mt_pop').length) $('.mt_pop').remove(); })
               .on('keydown', function(e) { if (e.key === 'Escape') $('.mt_pop').remove(); });
    $('#mt_q, #mt_active').on('input change', render);
    $('#mt_expand').on('click', function() { collapsed = {}; saveCollapsed(); render(); });
    $('#mt_collapse').on('click', function() { collapsed = {}; rows.forEach(function(r) { if (r.has_children) collapsed[r.id] = true; }); saveCollapsed(); render(); });
    $('#mt_add_root').on('click', function() { add({}); });
    $('#mt_cols_btn').on('click', function() { showModal('mt_cols_dialog', '760px'); });
    $('#mt_issue_btn').on('click', function() { selCount(); showModal('mt_issue_dialog', '520px'); });
    $('#mt_issue_go').on('click', makeIssues);

    // 끌어서 옮기기: 위 1/4 = 앞, 아래 1/4 = 뒤, 가운데 = 하위로
    var dragId = null;
    $g.on('mousedown', '.mt_handle', function() { $(this).closest('tr').attr('draggable', 'true'); });
    $g.on('dragstart', 'tr[data-id]', function(e) { dragId = $(this).data('id'); e.originalEvent.dataTransfer.effectAllowed = 'move'; e.originalEvent.dataTransfer.setData('text/plain', String(dragId)); $(this).addClass('mt_dragging'); });
    $g.on('dragover', 'tr[data-id]', function(e) {
      if (!dragId) return; e.preventDefault();
      var r = this.getBoundingClientRect(), y = e.originalEvent.clientY - r.top, zone = y < r.height / 4 ? 'before' : (y > r.height * 3 / 4 ? 'after' : 'inside');
      $g.find('tr').removeClass('mt_dz_before mt_dz_after mt_dz_inside'); $(this).addClass('mt_dz_' + zone).data('zone', zone);
    });
    $g.on('drop', 'tr[data-id]', function(e) {
      e.preventDefault(); var target = $(this).data('id'), zone = $(this).data('zone') || 'after';
      $g.find('tr').removeClass('mt_dz_before mt_dz_after mt_dz_inside');
      if (dragId && target !== dragId) move(dragId, 'drop', null, { target_id: target, where: zone });
      dragId = null;
    });
    $g.on('dragend', 'tr[data-id]', function() { $(this).removeAttr('draggable').removeClass('mt_dragging'); $g.find('tr').removeClass('mt_dz_before mt_dz_after mt_dz_inside'); dragId = null; });
  });
})(jQuery);
