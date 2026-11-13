// 터미널 탭 › 파일 창 — 목록 · 이동 · 받기 · 올리기(끌어다 놓기, 진행률) · 새 폴더 · 이름 바꾸기 · 삭제
// 운영 서버는 올리기·이름 바꾸기·삭제 전에 확인. 확인·입력은 패널 안 작은 상자(브라우저 alert/prompt 안 씀)
(function() {
  'use strict';
  document.addEventListener('DOMContentLoaded', function() {
    var box = document.getElementById('st_files'); if (!box) return;
    var d = box.dataset, prod = d.prod === '1';
    var $ = function(id) { return document.getElementById(id); };
    var btn = $('st_files_btn'), list = $('sf_list'), msg = $('sf_msg'), pathIn = $('sf_path');
    var cur = '', parent = null, loaded = false, busy = false;
    var token = function() { return document.querySelector('meta[name="csrf-token"]').content; };
    function esc(s) { var x = document.createElement('div'); x.textContent = s == null ? '' : String(s); return x.innerHTML; }
    function say(t, bad) { msg.textContent = t || ''; msg.className = 'sf_msg' + (bad ? ' is_bad' : ''); }
    function human(n) { if (n == null) return ''; var u = ['B', 'KB', 'MB', 'GB', 'TB'], i = 0; while (n >= 1024 && i < 4) { n /= 1024; i++; } return (i ? n.toFixed(1) : n) + ' ' + u[i]; }
    function layout() { document.dispatchEvent(new Event('ssh:layout')); }

    document.addEventListener('ssh:connected', function() { btn.disabled = false; });
    document.addEventListener('ssh:closed', function() { btn.disabled = true; say('터미널 연결이 끊겨 파일 창을 쓸 수 없습니다.', true); });
    btn.addEventListener('click', function() { toggle(box.hidden); });
    $('sf_close').addEventListener('click', function() { toggle(false); });
    function toggle(open) {
      box.hidden = !open; btn.setAttribute('aria-expanded', open ? 'true' : 'false'); btn.classList.toggle('on', open);
      document.body.classList.toggle('sf_open', open); layout();
      if (open && !loaded) load('');
    }

    // 확인·입력 상자 (패널 안)
    function ask(text, value, input) {
      return new Promise(function(resolve) {
        var w = document.createElement('div'); w.className = 'sf_ask'; w.setAttribute('role', 'dialog');
        w.innerHTML = '<p>' + esc(text) + '</p>' + (input ? '<input type="text" class="sf_in" value="' + esc(value || '') + '">' : '') +
          '<div class="sf_ask_btns"><button type="button" class="sf_btn">취소</button><button type="button" class="sf_btn sf_pri">확인</button></div>';
        box.appendChild(w);
        var inp = w.querySelector('input'), b = w.querySelectorAll('button');
        function done(v) { w.remove(); resolve(v); }
        b[0].onclick = function() { done(null); };
        b[1].onclick = function() { done(input ? inp.value.trim() : true); };
        w.addEventListener('keydown', function(e) { if (e.key === 'Escape') done(null); if (e.key === 'Enter') b[1].click(); });
        (inp || b[1]).focus(); if (inp) inp.select();
      });
    }
    function confirmProd(text) { return prod ? ask('[운영 서버] ' + text) : Promise.resolve(true); }

    function api(url, body) {
      var o = { credentials: 'same-origin', headers: { 'Accept': 'application/json', 'X-CSRF-Token': token() } };
      if (body) { o.method = 'POST'; o.body = body; }
      return fetch(url, o).then(function(r) { return r.json().catch(function() { return { ok: false, message: '응답을 읽지 못했습니다.' }; }); });
    }
    function form(obj) { var f = new FormData(); Object.keys(obj).forEach(function(k) { f.append(k, obj[k]); }); f.append('authenticity_token', token()); return f; }

    function load(path) {
      if (busy) return; busy = true; say('불러오는 중...');
      api(d.list + '?path=' + encodeURIComponent(path)).then(function(j) {
        busy = false;
        if (!j.ok) { say(j.message, true); return; }
        loaded = true; cur = j.path; parent = j.parent; pathIn.value = cur; $('sf_up').disabled = !parent;
        say(j.more ? '항목이 많아 일부만 보입니다' : j.entries.length + '개');
        render(j.entries);
      }, function() { busy = false; say('불러오지 못했습니다.', true); });
    }
    function render(items) {
      if (!items.length) { list.innerHTML = '<p class="sf_empty">비어 있습니다</p>'; return; }
      list.innerHTML = '<table class="sf_table"><thead><tr><th>이름</th><th>크기</th><th>수정 시각</th><th>권한</th><th></th></tr></thead><tbody>' +
        items.map(function(e, i) {
          return '<tr data-i="' + i + '"><td class="sf_name">' + (e.dir ? '<button type="button" class="sf_dir" data-act="open">📁 ' + esc(e.name) + (e.link ? ' ↪' : '') + '</button>'
                   : '<span class="sf_file">📄 ' + esc(e.name) + (e.link ? ' ↪' : '') + '</span>') + '</td>' +
            '<td class="sf_num">' + (e.dir ? '' : human(e.size)) + '</td><td class="sf_time">' + esc(e.mtime) + '</td><td class="sf_perm"><code>' + esc(e.perms) + '</code></td>' +
            '<td class="sf_acts">' + (e.dir ? '' : '<button type="button" class="sf_btn" data-act="get" title="받기">받기</button>') +
            '<button type="button" class="sf_btn" data-act="ren" title="이름 바꾸기" aria-label="이름 바꾸기 ' + esc(e.name) + '">✎</button>' +
            '<button type="button" class="sf_btn sf_del" data-act="del" title="삭제" aria-label="삭제 ' + esc(e.name) + '">🗑</button></td></tr>';
        }).join('') + '</tbody></table>';
      list._items = items;
    }
    function full(name) { return (cur === '/' ? '' : cur) + '/' + name; }
    list.addEventListener('click', function(ev) {
      var b = ev.target.closest('button[data-act]'); if (!b) return;
      var e = list._items[+b.closest('tr').dataset.i], p = full(e.name);
      if (b.dataset.act === 'open') load(p);
      else if (b.dataset.act === 'get') { var a = document.createElement('a'); a.href = d.download + '?path=' + encodeURIComponent(p); a.rel = 'noopener'; document.body.appendChild(a); a.click(); a.remove(); say('받는 중: ' + e.name); }
      else if (b.dataset.act === 'ren') ask('새 이름', e.name, true).then(function(n) {
        if (!n || n === e.name) return;
        confirmProd('이름을 바꿀까요? ' + e.name + ' → ' + n).then(function(ok) { if (ok) api(d.rename, form({ path: p, name: n })).then(after); });
      });
      else if (b.dataset.act === 'del') ask((prod ? '[운영 서버] ' : '') + (e.dir ? '빈 폴더만 지울 수 있습니다. ' : '') + e.name + ' 을(를) 삭제할까요?').then(function(ok) { if (ok) api(d['delete'], form({ path: p })).then(after); });
    });
    function after(j) { if (!j.ok) { say(j.message, true); return; } load(cur); }
    $('sf_up').addEventListener('click', function() { if (parent) load(parent); });
    $('sf_refresh').addEventListener('click', function() { load(cur); });
    $('sf_path_form').addEventListener('submit', function(e) { e.preventDefault(); load(pathIn.value.trim()); });
    $('sf_mkdir').addEventListener('click', function() {
      ask('새 폴더 이름', '', true).then(function(n) { if (n) confirmProd('폴더를 만들까요? ' + n).then(function(ok) { if (ok) api(d.mkdir, form({ dir: cur, name: n })).then(after); }); });
    });

    // 올리기 (진행률) — 고르기 또는 끌어다 놓기
    function upload(files) {
      if (!files || !files.length || !loaded) return;
      var names = [].map.call(files, function(f) { return f.name; }).join(', ');
      confirmProd(files.length + '개 파일을 ' + cur + ' 에 올릴까요? (' + names + ')').then(function(ok) {
        if (!ok) return;
        var f = new FormData(); [].forEach.call(files, function(x) { f.append('files[]', x); }); f.append('dir', cur); f.append('authenticity_token', token());
        var x = new XMLHttpRequest(); x.open('POST', d.upload); x.setRequestHeader('X-CSRF-Token', token()); x.setRequestHeader('Accept', 'application/json');
        x.upload.onprogress = function(e) { if (e.lengthComputable) say('올리는 중 ' + Math.round(e.loaded / e.total * 100) + '%'); };
        x.onload = function() { var j = {}; try { j = JSON.parse(x.responseText); } catch (e) { j = { ok: false, message: '올리지 못했습니다.' }; } if (j.ok) say(j.files.length + '개 올림'); after(j); };
        x.onerror = function() { say('올리지 못했습니다.', true); };
        x.send(f);
      });
    }
    // FileList 는 입력칸을 비우면 같이 비므로 먼저 배열로 복사
    $('sf_file').addEventListener('change', function() { var list = Array.prototype.slice.call(this.files); this.value = ''; upload(list); });
    var drop = $('sf_drop');
    box.addEventListener('dragover', function(e) { e.preventDefault(); drop.hidden = false; });
    box.addEventListener('dragleave', function(e) { if (!box.contains(e.relatedTarget)) drop.hidden = true; });
    box.addEventListener('drop', function(e) { e.preventDefault(); drop.hidden = true; upload(Array.prototype.slice.call(e.dataTransfer.files)); });
  });
})();
