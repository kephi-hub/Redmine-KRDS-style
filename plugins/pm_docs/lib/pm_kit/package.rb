# 검수용 일괄 다운로드 — 단계 폴더(01_착수 …)에 산출물별 최신 첨부 + 자동 생성 엑셀, 맨 위 산출물목록.xlsx
# 동시에 하나, tmp/pm_packages 에 만들고 1시간 뒤 정리
require 'zip'
require 'securerandom'

module PmKit
  module Package
    LOCK = Mutex.new

    module_function

    def dir
      d = Rails.root.join('tmp', 'pm_packages')
      FileUtils.mkdir_p(d)
      Dir.glob(d.join('*')).each { |f| FileUtils.rm_rf(f) if File.mtime(f) < 1.hour.ago }
      d
    end

    def clean(name)
      name.to_s.gsub(%r{[\\/:*?"<>|]+}, '_').strip.truncate(80, omission: '')
    end

    # 반환: [zip 경로, 파일 이름, { files:, auto:, missing: }]
    def build(project, list, auto: true, source: false)
      raise PmKit::Error, I18n.t(:error_pm_package_busy) unless LOCK.try_lock
      begin
        path = dir.join("#{SecureRandom.hex(8)}.zip").to_s
        stat = { files: 0, auto: 0, missing: 0 }
        phases = PmDeliverable::PHASES
        Zip::OutputStream.open(path) do |zos|
          zos.put_next_entry('산출물목록.xlsx')
          zos.write PmKit::Sheet.deliverables(list)
          list.each do |d|
            folder = format('%02d_%s/%s', phases.index(d.phase).to_i + 1, PmKit::Sheet::LABEL['phase'][d.phase], clean([d.code, d.name].compact.join('_')))
            put = false
            if (a = d.latest_attachment) && File.exist?(a.diskfile.to_s)
              zos.put_next_entry("#{folder}/#{clean(a.filename)}")
              File.open(a.diskfile, 'rb') { |io| IO.copy_stream(io, zos) }
              stat[:files] += 1
              put = true
            end
            if auto && d.auto_kind.present? && (source || !PmKit::AutoDocs.heavy?(d.auto_kind))
              PmKit::AutoDocs.generate(d.auto_kind, project).each do |name, data|
                zos.put_next_entry("#{folder}/#{clean(name)}")
                if data.is_a?(Hash)
                  File.open(data[:path], 'rb') { |io| IO.copy_stream(io, zos) }
                else
                  zos.write data
                end
                stat[:auto] += 1
                put = true
              end
            end
            stat[:missing] += 1 unless put
          end
        end
        [path, "산출물_#{project.identifier}_#{User.current.today.strftime('%Y%m%d')}.zip", stat]
      ensure
        LOCK.unlock if LOCK.owned?
      end
    end
  end

end
