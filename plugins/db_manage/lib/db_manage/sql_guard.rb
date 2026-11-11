# SQL 조회 문장 검사 — 조회 문장 한 개만 허용 (DB 쪽에서도 읽기 전용 트랜잭션으로 한 번 더 막음)
# - 허용: SELECT · WITH · SHOW · DESC/DESCRIBE · EXPLAIN SELECT/WITH · VALUES · TABLE(PostgreSQL)
# - 거부: 여러 문장(;), 변경·권한·실행 키워드, SELECT … INTO, FOR UPDATE/SHARE, LOCK, 파일 읽기·쓰기
module DbManage
  module SqlGuard
    module_function

    FIRST = %w(SELECT WITH SHOW DESC DESCRIBE EXPLAIN VALUES TABLE).freeze
    # (REPLACE·COMMENT 처럼 함수·컬럼 이름으로 흔히 쓰는 말은 빼고, 실제 차단은 DB 의 읽기 전용 트랜잭션이 함)
    BLOCK = %w(INSERT UPDATE DELETE MERGE UPSERT CREATE ALTER DROP TRUNCATE RENAME GRANT REVOKE CALL EXEC EXECUTE
               HANDLER COPY UNLOCK SET VACUUM REINDEX INTO OUTFILE DUMPFILE SHUTDOWN KILL PURGE FLUSH INSTALL UNINSTALL
               DBCC OPENROWSET OPENQUERY OPENDATASOURCE BULK XP_CMDSHELL SP_EXECUTESQL DBMS_SQL UTL_FILE UTL_HTTP).freeze

    # [정리된 문장, nil] 또는 [nil, 거부 이유]
    def check(sql)
      text = sql.to_s.strip
      return [nil, '조회 문장을 입력하세요.'] if text.empty?
      return [nil, '문장이 너무 깁니다 (2만 자 이하).'] if text.size > 20_000
      bare = strip_literals(strip_comments(text)).strip.sub(/;\s*\z/, '')
      return [nil, '문장은 하나만 실행할 수 있습니다 (; 로 여러 문장 불가).'] if bare.include?(';')
      words = bare.upcase.scan(/[A-Z_][A-Z0-9_$#]*/)
      first = words.first
      return [nil, "조회 문장만 실행할 수 있습니다 (#{FIRST.join(', ')} 로 시작)."] unless FIRST.include?(first)
      return [nil, 'EXPLAIN 은 SELECT·WITH 조회에만 쓸 수 있습니다.'] if first == 'EXPLAIN' && !(words[1..] - %w(ANALYZE VERBOSE FORMAT JSON TEXT COSTS BUFFERS EXTENDED PARTITIONS)).first.to_s.match?(/\A(SELECT|WITH)\z/)
      hit = (words[1..] & BLOCK) - (first == 'EXPLAIN' ? %w(ANALYZE) : [])
      hit -= %w(SET) if first == 'SHOW'
      return [nil, "허용하지 않는 키워드가 있습니다: #{hit.first(3).join(', ')}"] if hit.any?
      return [nil, 'FOR UPDATE / FOR SHARE (잠금) 는 쓸 수 없습니다.'] if bare.match?(/\bFOR\s+(UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b/i) || bare.match?(/\bLOCK\s+IN\s+SHARE\s+MODE\b/i)
      [text.sub(/;\s*\z/, ''), nil]
    end

    # 주석 제거 (-- … / # … / /* … */)
    def strip_comments(s)
      s.gsub(%r{/\*.*?\*/}m, ' ').gsub(/--[^\n]*/, ' ').gsub(/(^|\s)#[^\n]*/, ' ')
    end

    # 문자열·따옴표 이름 안의 글자는 검사하지 않음
    def strip_literals(s)
      s.gsub(/'(?:[^']|'')*'/, "''").gsub(/"(?:[^"]|"")*"/, '""').gsub(/`(?:[^`]|``)*`/, '``').gsub(/\[[^\]]*\]/, '[]')
    end
  end
end
