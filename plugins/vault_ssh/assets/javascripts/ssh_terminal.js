// 터미널 탭 — xterm.js 화면 + ActionCable(웹소켓 프로토콜 직접) 로 SSH 입출력
// 서버 → { t:'o', d:base64 } 출력 · { t:'s', s:'connecting|connected|closed|failed', m } 상태 · { t:'w', m } 경고
// 브라우저 → input { d } · resize { cols, rows } · close
(function() {
  'use strict';
  document.addEventListener('DOMContentLoaded', function() {
    var el = document.getElementById('st_term'), d = el.dataset;
    var $ = function(id) { return document.getElementById(id); };
    var size = 14;
    try { size = parseInt(localStorage.getItem('ssh_font'), 10) || 14; } catch (e) {}
    var term = new Terminal({
      cursorBlink: true, fontSize: size, scrollback: 5000, convertEol: false,
      fontFamily: 'D2Coding, "Cascadia Mono", Consolas, "Noto Sans Mono CJK KR", "Malgun Gothic", monospace',
      theme: { background: '#131416', foreground: '#e6e8ea', cursor: '#b1cefb', selectionBackground: '#33363d' }
    });
    var fit = new FitAddon.FitAddon();
    term.loadAddon(fit);
    term.open(el);
    fit.fit();
    term.focus();

    var state = 'init', ws = null, ident = null, started = null, timer = null;
    function setState(text, cls) { var s = $('st_state'); s.textContent = text; s.className = 'st_state' + (cls ? ' ' + cls : ''); }
    function note(text, cls) { var n = $('st_note'); n.textContent = text || ''; n.hidden = !text; n.className = 'st_note' + (cls ? ' ' + cls : ''); }
    function showAgain() { if (d.again) $('st_again').hidden = false; $('st_close').hidden = true; }
    function tick() {
      if (!started) return;
      var s = Math.floor((Date.now() - started) / 1000), p = function(n) { return (n < 10 ? '0' : '') + n; };
      $('st_time').textContent = p(Math.floor(s / 3600)) + ':' + p(Math.floor(s / 60) % 60) + ':' + p(s % 60);
    }
    function send(action, data) {
      if (!ws || ws.readyState !== 1 || state !== 'connected') return;
      data = data || {}; data.action = action;
      ws.send(JSON.stringify({ command: 'message', identifier: ident, data: JSON.stringify(data) }));
    }
    function bytes(b64) { var s = atob(b64), a = new Uint8Array(s.length); for (var i = 0; i < s.length; i++) a[i] = s.charCodeAt(i); return a; }
    function finish(text, cls) {
      if (state === 'closed') return;
      state = 'closed';
      clearInterval(timer);
      setState(text || d.closed, cls || 'is_off');
      term.write('\r\n\x1b[90m── ' + (text || d.closed) + ' ──\x1b[0m\r\n');
      showAgain();
      document.dispatchEvent(new Event('ssh:closed'));
      try { ws && ws.close(); } catch (e) {}
    }

    if (d.usable !== '1') { setState(d.closed, 'is_off'); note(d.used, 'is_warn'); showAgain(); }
    else connect();

    function connect() {
      state = 'connecting';
      setState(d.connecting);
      ident = JSON.stringify({ channel: 'SshConsole::TerminalChannel', ticket: d.ticket, cols: term.cols, rows: term.rows });
      ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/cable');
      ws.onmessage = function(ev) {
        var m = JSON.parse(ev.data);
        if (m.type === 'ping') return;
        if (m.type === 'welcome') { ws.send(JSON.stringify({ command: 'subscribe', identifier: ident })); return; }
        if (m.type === 'reject_subscription') { finish(d.used, 'is_bad'); return; }
        if (m.type === 'disconnect') { finish(); return; }
        var x = m.message; if (!x) return;
        if (x.t === 'o') term.write(bytes(x.d));
        else if (x.t === 'w') note(x.m, 'is_warn');
        else if (x.t === 's') {
          if (x.s === 'connecting') { setState(d.connecting); if (x.m) $('st_target').textContent = x.m; }
          else if (x.s === 'connected') {
            state = 'connected'; started = Date.now(); timer = setInterval(tick, 1000); setState('●', 'is_on');
            if (x.m) $('st_target').textContent = x.m;
            send('resize', { cols: term.cols, rows: term.rows });
            document.dispatchEvent(new Event('ssh:connected'));
            term.focus();
          }
          else if (x.s === 'failed') { note(x.m, 'is_bad'); finish(x.m, 'is_bad'); }
          else if (x.s === 'closed') finish(x.m);
        }
      };
      ws.onclose = function() { if (state !== 'closed') finish(); };
      ws.onerror = function() { if (state !== 'closed') finish(); };
    }

    term.onData(function(data) { note(''); send('input', { d: data }); });
    var rt = null;
    term.onResize(function(s) { clearTimeout(rt); rt = setTimeout(function() { send('resize', { cols: s.cols, rows: s.rows }); }, 150); });
    window.addEventListener('resize', function() { try { fit.fit(); } catch (e) {} });
    document.addEventListener('ssh:layout', function() { setTimeout(function() { try { fit.fit(); } catch (e) {} }, 30); });
    function font(delta) {
      size = Math.max(10, Math.min(28, size + delta)); term.options.fontSize = size;
      try { localStorage.setItem('ssh_font', size); } catch (e) {}
      fit.fit(); term.focus();
    }
    $('st_font_up').onclick = function() { font(1); };
    $('st_font_dn').onclick = function() { font(-1); };
    $('st_close').onclick = function() { send('close'); setTimeout(function() { finish(); }, 800); };
    $('st_again').onclick = function() {
      var t = document.querySelector('meta[name="csrf-token"]').content;
      fetch(d.again, { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-Token': t, 'Accept': 'application/json' } })
        .then(function(r) { return r.json(); }).then(function(j) { if (j.ok) location.href = j.url; else note(j.message, 'is_bad'); });
    };
    window.addEventListener('beforeunload', function(e) { if (state === 'connected') { e.preventDefault(); e.returnValue = ''; } });
  });
})();
