# 화면 녹화 — asciinema cast v2 (첫 줄 머리말 JSON + [초, "o", 글자] 한 줄씩), gzip
# 입력(키보드)은 남기지 않음 — 화면에 보이는 출력만 (비밀번호처럼 화면에 안 나오는 입력은 녹화에도 없음)
require 'zlib'
require 'json'

module SshConsole
  class Recorder
    attr_reader :file

    def initialize(session, cols, rows)
      dir = SshSession.root.join(session.project_id.to_s)
      FileUtils.mkdir_p(dir)
      @file = "#{session.project_id}/#{session.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.cast.gz"
      @gz = Zlib::GzipWriter.open(SshSession.root.join(@file).to_s)
      @t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @carry = ''.b
      @gz.puts({ version: 2, width: cols, height: rows, timestamp: Time.now.to_i, title: session.key_name, env: { TERM: 'xterm-256color' } }.to_json)
    end

    def elapsed
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @t0).round(4)
    end

    # 여러 바이트 글자(한글)가 둘로 잘려 오면 뒷부분을 다음 조각과 합침
    def output(bytes)
      data = @carry + bytes.b
      cut = data.bytesize
      3.times do
        break if data.byteslice(0, cut).dup.force_encoding('UTF-8').valid_encoding?
        cut -= 1
      end
      @carry = data.byteslice(cut, data.bytesize - cut) || ''.b
      text = data.byteslice(0, cut).force_encoding('UTF-8').scrub
      @gz.puts([elapsed, 'o', text].to_json) unless text.empty?
    end

    def resize(cols, rows)
      @gz.puts([elapsed, 'r', "#{cols}x#{rows}"].to_json)
    end

    def close
      output(''.b) unless @carry.empty?
      @gz.close
    rescue StandardError
      nil
    end
  end
end
