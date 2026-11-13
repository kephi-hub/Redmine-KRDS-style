// 녹화 재생 — asciinema cast v2 를 xterm.js 에 시간 순서대로 (긴 멈춤은 2초로 줄임), 위치 이동은 처음부터 빠르게 다시 그림
(function() {
  'use strict';
  document.addEventListener('DOMContentLoaded', function() {
    var box = document.getElementById('ss_player'); if (!box) return;
    var term = new Terminal({ fontSize: 13, scrollback: 3000, disableStdin: true, cursorBlink: false,
      fontFamily: 'D2Coding, "Cascadia Mono", Consolas, "Noto Sans Mono CJK KR", monospace', theme: { background: '#131416', foreground: '#e6e8ea' } });
    var ev = [], total = 0, pos = 0, at = 0, playing = false, speed = 1, last = 0, raf = null;
    var $ = function(id) { return document.getElementById(id); };
    function fmt(s) { s = Math.floor(s); return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2); }
    fetch(box.dataset.cast, { credentials: 'same-origin' }).then(function(r) { return r.text(); }).then(function(text) {
      var lines = text.split('\n').filter(Boolean), head = {};
      try { head = JSON.parse(lines.shift()); } catch (e) {}
      term.resize(Math.min(head.width || 120, 250), Math.min(head.height || 30, 80));
      term.open($('ss_screen'));
      var shift = 0, prev = 0;
      lines.forEach(function(l) {
        try { var e = JSON.parse(l); var gap = e[0] - prev; if (gap > 2) shift += gap - 2; prev = e[0]; ev.push([e[0] - shift, e[1], e[2]]); } catch (x) {}
      });
      total = ev.length ? ev[ev.length - 1][0] : 0;
      clock();
    });
    function clock() { $('ss_clock').textContent = fmt(at) + ' / ' + fmt(total); $('ss_seek').value = total ? Math.round(at / total * 1000) : 0; }
    function apply(e) {
      if (e[1] === 'o') term.write(e[2]);
      else if (e[1] === 'r') { var m = /^(\d+)x(\d+)$/.exec(e[2]); if (m) term.resize(Math.min(+m[1], 250), Math.min(+m[2], 80)); }
    }
    function step(now) {
      if (!playing) return;
      at += (now - last) / 1000 * speed; last = now;
      while (pos < ev.length && ev[pos][0] <= at) apply(ev[pos++]);
      clock();
      if (pos >= ev.length) { playing = false; $('ss_play').textContent = '▶'; return; }
      raf = requestAnimationFrame(step);
    }
    function play() { if (pos >= ev.length) seek(0); playing = true; $('ss_play').textContent = '❚❚'; last = performance.now(); raf = requestAnimationFrame(step); }
    function pause() { playing = false; cancelAnimationFrame(raf); $('ss_play').textContent = '▶'; }
    function seek(t) {
      term.reset(); pos = 0; at = t;
      var buf = '';
      while (pos < ev.length && ev[pos][0] <= at) { var e = ev[pos++]; if (e[1] === 'o') buf += e[2]; else { if (buf) { term.write(buf); buf = ''; } apply(e); } }
      if (buf) term.write(buf);
      clock();
    }
    $('ss_play').onclick = function() { playing ? pause() : play(); };
    $('ss_speed').onchange = function() { speed = +this.value || 1; };
    $('ss_seek').oninput = function() { var was = playing; pause(); seek(total * this.value / 1000); if (was) play(); };
  });
})();
