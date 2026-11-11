/* Mermaid 공통 (KRDS UI) — mermaid.min.js 11.4.1(MIT) 을 플러그인에 포함, 인터넷 연결 불필요
   - 본문의 ```mermaid 블록(<pre><code data-language="mermaid">)을 그림으로 (블록이 있을 때만 불러옴, 오류면 원문 유지)
   - window.krdsMermaid() : Mermaid 를 불러와 Promise 로 넘김 (DB ERD·메뉴 구조도 화면에서 사용)
   - window.krdsSaveSvg(svg, 이름) / window.krdsSavePng(svg, 이름) : 그린 그림을 SVG·PNG(2배)로 저장 */
(function() {
  var loading = null;
  window.krdsMermaidConfig = {
    startOnLoad: false, securityLevel: 'strict', htmlLabels: false, theme: 'base',
    er: { useMaxWidth: false, layoutDirection: 'TB' },
    flowchart: { useMaxWidth: false, htmlLabels: false, curve: 'basis', nodeSpacing: 24, rankSpacing: 48 },
    themeVariables: {
      // PC 에 설치된 글꼴을 먼저 — SVG·PNG 로 내려받을 때 웹 글꼴(Pretendard)을 쓸 수 없어 글자 폭이 달라지는 것을 막음
      fontFamily: '"Malgun Gothic","맑은 고딕","Apple SD Gothic Neo","Noto Sans KR","Noto Sans CJK KR",sans-serif', fontSize: '13px',
      primaryColor: '#ecf2fe', primaryBorderColor: '#256ef4', primaryTextColor: '#1e2124',
      lineColor: '#6d7882', secondaryColor: '#f4f5f6', tertiaryColor: '#ffffff',
      attributeBackgroundColorOdd: '#ffffff', attributeBackgroundColorEven: '#f4f5f6'
    }
  };
  window.krdsMermaid = window.dbMermaid = function() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (!loading) {
      loading = new Promise(function(ok, no) {
        var s = document.createElement('script');
        s.src = window.KRDS_MERMAID_SRC; s.onload = function() { window.mermaid.initialize(window.krdsMermaidConfig); ok(window.mermaid); };
        s.onerror = no; document.head.appendChild(s);
      });
    }
    return loading;
  };
  function svgText(svgEl) {
    var vb = svgEl.viewBox.baseVal, c = svgEl.cloneNode(true);
    c.setAttribute('xmlns', 'http://www.w3.org/2000/svg'); c.setAttribute('width', vb.width); c.setAttribute('height', vb.height); c.removeAttribute('style');
    var bg = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    bg.setAttribute('x', vb.x); bg.setAttribute('y', vb.y); bg.setAttribute('width', vb.width); bg.setAttribute('height', vb.height); bg.setAttribute('fill', '#ffffff');
    c.insertBefore(bg, c.firstChild);
    return { text: '<?xml version="1.0" encoding="UTF-8"?>\n' + new XMLSerializer().serializeToString(c), w: vb.width, h: vb.height };
  }
  function save(blob, name) {
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
    setTimeout(function() { URL.revokeObjectURL(a.href); a.remove(); }, 500);
  }
  window.krdsSaveSvg = function(svgEl, name) { save(new Blob([svgText(svgEl).text], { type: 'image/svg+xml' }), name + '.svg'); };
  window.krdsSavePng = function(svgEl, name) {
    var s = svgText(svgEl), img = new Image(), k = 2;
    img.onload = function() {
      var cv = document.createElement('canvas'); cv.width = s.w * k; cv.height = s.h * k;
      var g = cv.getContext('2d'); g.fillStyle = '#ffffff'; g.fillRect(0, 0, cv.width, cv.height); g.drawImage(img, 0, 0, cv.width, cv.height);
      cv.toBlob(function(b) { save(b, name + '.png'); }, 'image/png');
    };
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(s.text);
  };
  var seq = 0;
  function render() {
    var blocks = document.querySelectorAll('pre > code[data-language="mermaid"]:not([data-mm])');
    if (!blocks.length) return;
    window.krdsMermaid().then(function(mm) {
      blocks.forEach(function(code) {
        code.setAttribute('data-mm', '1');
        var pre = code.parentNode, id = 'mm_' + (++seq);
        mm.render(id, code.textContent).then(function(r) {
          var box = document.createElement('div');
          box.className = 'mm_box'; box.innerHTML = r.svg;
          pre.style.display = 'none'; pre.parentNode.insertBefore(box, pre.nextSibling);
        }).catch(function() {
          var bad = document.getElementById('d' + id); if (bad) bad.remove();
        });
      });
    });
  }
  document.addEventListener('DOMContentLoaded', render);
  // 위키 미리보기 등 나중에 들어온 본문
  if (window.jQuery) jQuery(document).ajaxComplete(function() { setTimeout(render, 0); });
})();
