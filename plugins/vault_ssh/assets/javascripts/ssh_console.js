// 접속정보(Vault) 화면 — [▶ 접속] · [⚙ SSH 설정] 모달, 상세 화면 버튼·[접속 기록] 자리 옮기기
(function($) {
  'use strict';
  var T = {
    profile: 'SSH 설정', prodTitle: '운영 서버 접속', askTitle: '접속 정보 입력', open: '터미널 열기', cancel: '취소',
    reason: '접속 사유', reasonPh: '예) 배포 후 로그 확인 #123', confirm: '프로젝트 식별자', user: '아이디', password: '비밀번호',
    prodHelp: '운영 서버 접속은 사유와 프로젝트 식별자를 입력해야 하며, 화면이 녹화됩니다.',
    opening: '터미널을 여는 중...', testing: '연결하는 중...', ok: '연결됨', fail: '실패', skip: '시도 안 함', saved: 'SSH 설정을 저장했습니다.',
    popup: '새 탭을 열지 못했습니다. 브라우저의 팝업 차단을 이 사이트에서 해제해 주세요.', error: '요청을 처리하지 못했습니다.'
  };
  function token() { return $('meta[name="csrf-token"]').attr('content'); }
  function esc(s) { return $('<div>').text(s == null ? '' : String(s)).html(); }
  function dialog(msg) { return window.KrdsDialog ? window.KrdsDialog.alert(msg) : Promise.resolve(window.alert(msg)); }

  // 새 탭을 먼저 열고(팝업 차단 피함) 접속표를 받아 그 탭을 터미널로 보냄
  function openTerminal(url, data) {
    var w = window.open('', '_blank');
    if (!w) { dialog(T.popup); return Promise.resolve(false); }
    try { w.document.title = T.opening; w.document.body.innerHTML = '<p style="font:16px sans-serif;padding:24px">' + T.opening + '</p>'; } catch (e) {}
    var body = new URLSearchParams(data || {});
    body.append('authenticity_token', token());
    return fetch(url, { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-Token': token(), 'Accept': 'application/json' }, body: body })
      .then(function(r) { return r.json().catch(function() { return { ok: false, message: T.error }; }); })
      .then(function(j) {
        if (j.ok) { w.location.href = j.url; return true; }
        w.close(); dialog(j.message || T.error); return false;
      }, function() { w.close(); dialog(T.error); return false; });
  }

  // [▶ 접속]
  $(document).on('click', '[data-ssh-connect]', function(e) {
    e.preventDefault();
    var b = this.dataset, prod = b.env === 'prod', ask = b.auth === 'ask';
    if (!prod && !ask) { openTerminal(b.sshConnect, {}); return; }
    var html = '<form class="sp_form sp_go">' +
      (prod ? '<p class="sp_help sp_warn">' + esc(T.prodHelp) + '</p>' +
        '<label class="sp_field"><span>' + T.reason + ' *</span><input type="text" name="reason" maxlength="255" required placeholder="' + esc(T.reasonPh) + '"></label>' +
        '<label class="sp_field"><span>' + T.confirm + ' (<code>' + esc(b.project) + '</code>) *</span><input type="text" name="confirm" required autocomplete="off"></label>' : '') +
      (ask ? '<label class="sp_field"><span>' + T.user + '</span><input type="text" name="ask_user" value="' + esc(b.login) + '" autocomplete="off"></label>' +
        '<label class="sp_field"><span>' + T.password + ' *</span><input type="password" name="ask_password" required autocomplete="off"></label>' : '') +
      '<div class="sp_btns"><span class="sp_gap"></span><button type="button" class="kd_btn sp_cancel">' + T.cancel + '</button>' +
      '<button type="submit" class="kd_btn kd_pri">' + T.open + '</button></div></form>';
    var p = window.KrdsDialog.panel({ title: (prod ? T.prodTitle : T.askTitle) + ' — ' + b.name, html: html, wide: false });
    p.body.find('.sp_cancel').on('click', p.close);
    p.body.find('form').on('submit', function(ev) {
      ev.preventDefault();
      var data = {}; $(this).serializeArray().forEach(function(x) { data[x.name] = x.value; });
      openTerminal(b.sshConnect, data).then(function(ok) { if (ok) p.close(); });
    });
  });

  // [⚙ SSH 설정]
  $(document).on('click', '[data-ssh-profile]', function(e) {
    e.preventDefault();
    var url = this.dataset.sshProfile, name = this.dataset.name;
    fetch(url, { credentials: 'same-origin', headers: { 'Accept': 'text/html' } }).then(function(r) {
      if (!r.ok) throw new Error(r.status);
      return r.text();
    }).then(function(html) {
      var p = window.KrdsDialog.panel({ title: T.profile + ' — ' + name, html: html });
      wireProfile(p);
    }).catch(function() { dialog(T.error); });
  });

  function wireProfile(p) {
    var $f = p.body.find('#ssh_profile_form'), $hops = $f.find('.sp_hops'), max = +$hops.data('max') || 3;
    function sync() {
      var auth = $f.find('input[name="ssh[auth]"]:checked').val();
      $f.find('.sp_keyfile').prop('hidden', auth !== 'key');
      $f.find('.sp_ask').prop('hidden', auth !== 'ask');
      var prod = $f.find('input[name="ssh[env]"]:checked').val() === 'prod';
      $f.find('input[name="ssh[record]"]').prop('disabled', prod).prop('checked', prod || $f.find('input[name="ssh[record]"]').prop('checked'));
      $hops.find('.sp_hop').each(function() {
        var k = $(this).find('input[type=radio]:checked').val();
        $(this).find('.sp_hop_key').prop('hidden', k !== 'key');
        $(this).find('.sp_hop_direct').prop('hidden', k !== 'direct');
      });
      $hops.find('.sp_add').prop('hidden', $hops.find('.sp_hop').length >= max);
    }
    function renumber() {
      $hops.find('.sp_hop').each(function(i) {
        $(this).attr('data-i', i).find('legend').text('경유 ' + (i + 1));
        $(this).find('[name^="ssh[hops]"]').each(function() { this.name = this.name.replace(/ssh\[hops\]\[[^\]]*\]/, 'ssh[hops][' + i + ']'); });
      });
    }
    $f.on('change', 'input[type=radio]', sync);
    $f.on('click', '.sp_hop_del', function() { $(this).closest('.sp_hop').remove(); renumber(); sync(); });
    $f.on('click', '.sp_add', function() {
      var n = $hops.find('.sp_hop').length;
      if (n >= max) return;
      var tpl = document.getElementById('sp_hop_tpl').innerHTML.replace(/__I__/g, n);
      $(tpl).insertBefore($(this));
      renumber(); sync();
    });
    $f.on('click', '.sp_cancel', p.close);
    $f.on('click', '.sp_test_btn', function() {
      var $out = $f.find('.sp_test').html('<p class="sp_dim">' + T.testing + '</p>');
      var btn = $(this).prop('disabled', true);
      $f.find('input[name="ssh[learned_fp][]"]').remove();
      post($f.data('test'), $f).then(function(j) {
        btn.prop('disabled', false);
        var rows = (j.steps || []).map(function(s) {
          var st = s.ok === true ? 'ok' : (s.ok === false ? 'ng' : 'na');
          return '<li data-s="' + st + '"><strong>' + esc(s.label) + '</strong> <code>' + esc(s.target) + '</code> ' +
            '<span class="sp_st">' + (st === 'ok' ? T.ok : st === 'ng' ? T.fail : T.skip) + '</span>' +
            (s.fp ? '<br><span class="sp_dim">' + esc(s.fp) + '</span>' : '') + (s.message ? '<br><span class="sp_err">' + esc(s.message) + '</span>' : '') + '</li>';
        }).join('');
        $out.html((j.ok ? '<p class="sp_good">✓ ' + T.ok + (j.seconds != null ? ' — ' + j.seconds + 's' : '') + '</p>' : '<p class="sp_err">' + esc(j.message || T.fail) + '</p>') +
                  (rows ? '<ol class="sp_steps">' + rows + '</ol>' : ''));
        if (j.ok) (j.steps || []).forEach(function(s) { $f.append($('<input type="hidden" name="ssh[learned_fp][]">').val(s.fp || '')); });
      }, function() { btn.prop('disabled', false); $out.html('<p class="sp_err">' + T.error + '</p>'); });
    });
    $f.on('submit', function(e) {
      e.preventDefault();
      post($f.attr('action'), $f).then(function(j) {
        if (!j.ok) { $f.find('.sp_test').html('<p class="sp_err">' + esc(j.message || T.error) + '</p>'); return; }
        p.close();
        if (window.krdsToast) window.krdsToast(j.message || T.saved);
        setTimeout(function() { location.reload(); }, 600);
      }, function() { $f.find('.sp_test').html('<p class="sp_err">' + T.error + '</p>'); });
    });
    sync();
  }

  function post(url, $form) {
    var fd = new FormData($form[0]);
    return fetch(url, { method: 'POST', credentials: 'same-origin', headers: { 'X-CSRF-Token': token(), 'Accept': 'application/json' }, body: fd })
      .then(function(r) { return r.json(); });
  }

  // 상세 화면 버튼은 제목 옆으로, [접속 기록] 은 오른쪽 위 버튼 줄로
  $(function() {
    var d = document.getElementById('ssh_detail_btns'), h = document.querySelector('#content h2');
    if (d && h) { h.insertAdjacentElement('afterend', d); d.hidden = false; }
    var a = document.getElementById('ssh_sessions_link'), c = document.querySelector('#content > .contextual');
    if (a && c) { c.insertBefore(a, c.firstChild); a.hidden = false; }
  });
})(jQuery);
