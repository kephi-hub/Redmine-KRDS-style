# 개인정보 컬럼 자동 후보 — 컬럼 이름 패턴, 컬럼 설명, 용어사전 용어 이름으로 분류를 짐작 (사람이 확정해야 저장)
module DbManage
  module Privacy
    module_function

    # [분류, 이름 패턴, 설명·용어 패턴] — 위에서부터 먼저 맞는 것
    RULES = [
      ['password', /(\A|_)(pw|pwd|passwd|password|pswd|pass|passwd_hash|pwd_hash)(_|\z)|secret/i, /비밀번호|패스워드|비번|암호(?!화)/],
      ['unique_id', /jumin|(\A|_)(ssn|rrn|jmno|rsdnt_?no|resident_?no|res_?no)(_|\z)|passport|psprt|(\A|_)(drv|driver|dl)_?(lic|no|num)|frgnr|alien_?no|frgn_?no/i,
       /주민(등록)?번호|여권|운전면허|외국인\s*등록/],
      ['bio', /finger|iris|(\A|_)face_?(img|tmpl|data)|(\A|_)bio_?(data|info|tmpl)/i, /지문|홍채|안면|생체|바이오|정맥/],
      ['finance', /(\A|_)(acct|acnt|account|bank_?acct|bank_?no|bnk_?acnt)_?(no|num)?(_|\z)|(\A|_)(card|crd)_?(no|num)(_|\z)|cardnum/i,
       /계좌|카드\s*번호|신용카드/],
      ['sensitive', /(\A|_)(health|disease|disab|religion|criminal)/i, /건강|병력|질병|장애|종교|정당|노동조합|노조|성생활|범죄|유전/],
      ['personal', /(\A|_)(tel|phone|mobile|hp|cell|mbl|mbtl|telno|telnum|phon)(_?no|_?num)?(_|\z)|e_?mail|(\A|_)addr|address|(\A|_)zip_?(cd|code)?(_|\z)|birth|brth|bday|(\A|_)(user|usr|cust|mbr|member|emp|psn|rcvr|sndr|aplcnt|apl|ptnt|stdnt)_?(nm|name)(_|\z)|(\A|_)ip_?addr/i,
       /성명|(고객|회원|사용자|신청인|신청자|담당자|수신자|발신자|수령인|직원|학생|환자|보호자|대표자|예금주|작성자)\s*(명|이름)|전화|휴대|핸드폰|연락처|(?<!URL\s)(?<!URL)주소|이메일|e-?mail|생년월일|생일|우편번호/i]
    ].freeze
    # 이런 끝말은 값이 아니라 여부·코드·개수라서 제외 (tel_yn, addr_cd …)
    SKIP = /(_yn|_flag|_cnt|_count|_cd|_code|_type|_tp|_seq|_id)\z|(\A|_)(is|has|use)_/i
    # 이름이 그대로 개인정보인 흔한 컬럼
    EXACT = { 'NAME' => 'personal', 'NM' => 'personal', 'EMAIL' => 'personal', 'PHONE' => 'personal', 'MOBILE' => 'personal', 'BIRTHDAY' => 'personal' }.freeze

    # 컬럼 하나 → [분류, 근거] 또는 nil
    def guess(column, term = nil)
      name = column[:name].to_s
      text = [column[:comment], term&.name].compact.join(' ')
      return [EXACT[name.upcase], :name] if EXACT[name.upcase]
      skip = name.match?(SKIP)
      RULES.each do |cat, name_re, text_re|
        return [cat, :comment] if text.present? && text.match?(text_re) && !(skip && text.match?(/여부|코드|구분|건수|일시|일자/))
        return [cat, :name] if !skip && name.match?(name_re)
      end
      nil
    end

    # 스냅샷 전체에서 후보: [{ table:, column:, category:, reason:, col: }] (뷰 제외, 이미 저장된 컬럼 제외)
    def candidates(snap, terms, saved_keys)
      snap[:tables].reject { |t| t[:view] }.flat_map do |t|
        (snap[:columns][t[:name]] || []).filter_map do |c|
          next if saved_keys.include?("#{t[:name]}.#{c[:name]}")
          term = terms && terms[c[:name].to_s.upcase]
          cat, reason = guess(c, term)
          { table: t[:name], table_comment: t[:comment], column: c[:name], category: cat, reason: reason, col: c } if cat
        end
      end
    end
  end
end
