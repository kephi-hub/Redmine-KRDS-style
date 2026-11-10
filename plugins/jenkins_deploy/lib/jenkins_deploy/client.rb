# Jenkins 원격 API 호출 — Net::HTTP 만 사용 (외부 gem 없음)
# 인증: Basic(계정:API 토큰). API 토큰 요청은 Jenkins 가 CSRF crumb 를 요구하지 않음
require 'net/http'
require 'json'
require 'uri'

module JenkinsDeploy
  class Error < StandardError; end
  class NotFound < Error; end

  class Client
    BUILD_FIELDS = 'number,result,building,timestamp,duration,estimatedDuration,url,' \
                   'actions[parameters[name,value],causes[shortDescription,userId,userName]],' \
                   'changeSets[kind,items[commitId,msg,author[fullName]]],changeSet[kind,items[commitId,msg,author[fullName]]]'
    PARAM_FIELDS = 'property[parameterDefinitions[name,type,description,choices,defaultParameterValue[value]]]'

    # Jenkins 응답의 매개변수 정의 → [{name:, type:, description:, default:, choices:}]
    def self.parse_definitions(data)
      Array(data['property']).flat_map { |p| Array(p && p['parameterDefinitions']) }.filter_map do |d|
        next if d['name'].blank?
        { name: d['name'], type: d['type'].to_s, description: d['description'].to_s,
          default: d.dig('defaultParameterValue', 'value'), choices: Array(d['choices']).map(&:to_s) }
      end
    end

    def initialize(server)
      @server = server
      @base = URI(server.url.to_s.chomp('/'))
    end

    # 연결 시험: Jenkins 버전과 인증된 계정 이름
    def who_am_i
      res = request(:get, '/whoAmI/api/json')
      data = parse(res)
      { version: res['X-Jenkins'], name: data['name'], authenticated: data['authenticated'] }
    end

    # 작업에 정의된 매개변수 (없으면 [])
    def parameter_definitions(job_path)
      self.class.parse_definitions(get_json("#{job_url(job_path)}/api/json", tree: PARAM_FIELDS))
    end

    # 배포 화면용: 최근 빌드와 매개변수 정의를 한 번에
    def job_info(job_path, limit = 20)
      data = get_json("#{job_url(job_path)}/api/json", tree: "builds[#{BUILD_FIELDS}]{0,#{limit.to_i}},#{PARAM_FIELDS}")
      { builds: Array(data['builds']), params: self.class.parse_definitions(data) }
    end

    # 배포 실행 → Jenkins 대기열 번호 반환
    # 작업에 매개변수가 있으면 정의된 이름만 골라 buildWithParameters, 없으면 build
    def trigger(job_path, params, definitions = nil)
      names = (definitions || parameter_definitions(job_path)).map { |d| d[:name] }
      if names.any?
        form = params.select { |k, _| names.include?(k) }
        res = request(:post, "#{job_url(job_path)}/buildWithParameters", form: form)
      else
        res = request(:post, "#{job_url(job_path)}/build", form: {})
      end
      raise Error, I18n.t(:error_jenkins_bad_response, code: res.code) unless res.code.to_i == 201
      res['Location'].to_s[%r{/queue/item/(\d+)}, 1]&.to_i or raise Error, I18n.t(:error_jenkins_no_queue)
    end

    def queue_item(queue_id)
      get_json("/queue/item/#{queue_id.to_i}/api/json")
    end

    def build(job_path, number)
      get_json("#{job_url(job_path)}/#{number.to_i}/api/json", tree: BUILD_FIELDS)
    end

    def builds(job_path, limit = 20)
      data = get_json("#{job_url(job_path)}/api/json", tree: "builds[#{BUILD_FIELDS}]{0,#{limit.to_i}}")
      Array(data['builds'])
    end

    # 폴더 안 작업: a/b → /job/a/job/b
    def job_url(job_path)
      '/' + job_path.to_s.split('/').reject(&:blank?).map { |s| "job/#{ERB::Util.url_encode(s)}" }.join('/')
    end

    private

    def get_json(path, query = {})
      parse(request(:get, path, query: query))
    end

    def parse(res)
      JSON.parse(res.body.to_s)
    rescue JSON::ParserError
      raise Error, I18n.t(:error_jenkins_bad_response, code: res.code)
    end

    def request(method, path, query: {}, form: nil)
      uri = @base.dup
      uri.path = @base.path.to_s + path
      uri.query = URI.encode_www_form(query) if query.present?
      req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
      req.basic_auth(@server.username.to_s, @server.token.to_s)
      req.set_form_data(form) if form
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl? && !@server.verify_ssl?
      http.open_timeout = http.read_timeout = @server.timeout.to_i.clamp(1, 60)
      res = http.start { |h| h.request(req) }
      case res.code.to_i
      when 200..399 then res
      when 401, 403 then raise Error, I18n.t(:error_jenkins_auth)
      when 404 then raise NotFound, I18n.t(:error_jenkins_not_found)
      else raise Error, I18n.t(:error_jenkins_bad_response, code: res.code)
      end
    rescue Error
      raise
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError => e
      Rails.logger.warn "[jenkins_deploy] #{@server.url}: #{e.class}: #{e.message}"
      raise Error, I18n.t(:error_jenkins_connect)
    end
  end
end
