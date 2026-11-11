/* Redmine 본문의 ```mermaid 블록(<pre><code data-language="mermaid">)을 그림으로 — DB 관리 플러그인
   블록이 있을 때만 mermaid.min.js(플러그인 안에 포함, 11.4.1) 를 불러오고, 오류면 원문을 그대로 둠 */
(function() {
  var loading = null;
  window.dbMermaidConfig = {
    startOnLoad: false, securityLevel: 'strict', htmlLabels: false, theme: 'base',
    er: { useMaxWidth: false, layoutDirection: 'TB' },
    themeVariables: {
      // PC 에 설치된 글꼴을 먼저 — SVG·PNG 로 내려받을 때 웹 글꼴(Pretendard)을 쓸 수 없어 글자 폭이 달라지는 것을 막음
      fontFamily: '"Malgun Gothic","맑은 고딕","Apple SD Gothic Neo","Noto Sans KR","Noto Sans CJK KR",sans-serif', fontSize: '13px',
      primaryColor: '#ecf2fe', primaryBorderColor: '#256ef4', primaryTextColor: '#1e2124',
      lineColor: '#6d7882', secondaryColor: '#f4f5f6', tertiaryColor: '#ffffff',
      attributeBackgroundColorOdd: '#ffffff', attributeBackgroundColorEven: '#f4f5f6'
    }
  };
  window.dbMermaid = function() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (!loading) {
      loading = new Promise(function(ok, no) {
        var s = document.createElement('script');
        s.src = window.DB_MERMAID_SRC; s.onload = function() { window.mermaid.initialize(window.dbMermaidConfig); ok(window.mermaid); };
        s.onerror = no; document.head.appendChild(s);
      });
    }
    return loading;
  };
  var seq = 0;
  function render() {
    var blocks = document.querySelectorAll('pre > code[data-language="mermaid"]:not([data-mm])');
    if (!blocks.length) return;
    window.dbMermaid().then(function(mm) {
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
