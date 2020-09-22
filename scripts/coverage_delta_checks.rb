require 'json'
require 'openssl'
require 'uri'
require 'net/http'
require 'time'
require 'base64'

FileDiff = Struct.new(:filename, :added_lines)

class SimplecovDelta
  class << self
    def mean(array)
      array.sum.to_f / array.length
    end

    def extract_delta
      git_diff = `git diff origin/master.. --no-color -U0`

      each_diff_output = git_diff.split("\n")

      files_diff = []

      each_diff_output.each_with_index do |line, index|
        if line.start_with?('diff --git a/')
          filename = line.scan(/diff --git a\/(.+)\s/)[0].first
          files_diff << FileDiff.new(filename, [])
        elsif line.start_with?('@@')
          current_file_diff = files_diff.last
          first_line_changed = line.scan(/@@ -.+\+(.\d?)/)[0].first.to_i
          offset = 1
          while each_diff_output[index + offset] && !each_diff_output[index + offset].start_with?('@@ -', 'diff')
            if each_diff_output[index + offset].start_with?('+')
              current_file_diff.added_lines << first_line_changed + offset - 1
            end
            offset += 1
          end
        end
      end

      files_diff
    end

    def coverage_results
      @coverage_results ||= JSON.parse(File.read('coverage/.resultset.json')).first.last['coverage']
    end

    def total_coverage
      coverage_each_file = []
      coverage_results.each do |_filename, coverage_by_line|
        lines = coverage_by_line['lines']
        lines.compact!
        total = lines.size
        with_coverage = lines.count { |line| line > 0 }
        coverage_each_file << with_coverage.to_f / total * 100
      end
      mean(coverage_each_file)
    end

    def calculate_delta_coverage(files_diff)
      tested_lines_score = {}

      coverage_results.each do |filename, coverage_by_line|
        file_diff = files_diff.detect { |f| filename.end_with?(f.filename) }
        next unless file_diff

        coverage_by_line = coverage_by_line['lines']
        covered_lines = 0
        relevant_lines = file_diff.added_lines.size
        file_diff.added_lines.each do |line_number|
          covered = coverage_by_line[line_number - 1]
          if covered.nil?
            relevant_lines -= 1
          elsif covered > 0
            covered_lines += 1
          end
        end
        tested_lines_score[file_diff.filename] = covered_lines.to_f / relevant_lines * 100
      end

      tested_lines_score
      { files: tested_lines_score, mean: mean(tested_lines_score.values).round(2), global: total_coverage.round(2) }
    end
  end
end

class JWT
  class << self
    def encode(payload, key, algorithm = 'HS256', header_fields = {})
      algorithm ||= 'none'
      segments = []
      segments << encoded_header(algorithm, header_fields)
      segments << encoded_payload(payload)
      segments << encoded_signature(segments.join('.'), key, algorithm)
      segments.join('.')
    end

    def encoded_header(algorithm = 'HS256', header_fields = {})
      header = { 'typ' => 'JWT', 'alg' => algorithm }.merge(header_fields)
      base64url_encode(JSON.generate(header))
    end

    def encoded_payload(payload)
      raise ArgumentError, 'exp claim must be an integer' if payload['exp'] && payload['exp'].is_a?(Time)
      base64url_encode(JSON.generate(payload))
    end

    def encoded_signature(signing_input, key, algorithm)
      if algorithm == 'none'
        ''
      else
        signature = sign(algorithm, signing_input, key)
        base64url_encode(signature)
      end
    end

    def base64url_encode(str)
      Base64.encode64(str).tr('+/', '-_').gsub(/[\n=]/, '')
    end

    def sign_rsa(algorithm, msg, private_key)
      private_key.sign(OpenSSL::Digest.new(algorithm.sub('RS', 'sha')), msg)
    end

    def sign(algorithm, msg, key)
      if %w(HS256 HS384 HS512).include?(algorithm)
        sign_hmac(algorithm, msg, key)
      elsif %w(RS256 RS384 RS512).include?(algorithm)
        sign_rsa(algorithm, msg, key)
      elsif %w(ES256 ES384 ES512).include?(algorithm)
        sign_ecdsa(algorithm, msg, key)
      else
        raise NotImplementedError, 'Unsupported signing method'
      end
    end
  end
end

class GithubApp
  SECRET_KEY = ENV['SECRET_KEY']
  GITHUB_APP_ID = ENV['APP_ID']
  GITHUB_APP_INSTALLATION_ID = ENV['APP_INSTALLATION_ID']

  def initialize(delta_coverage)
    @delta_coverage = delta_coverage
  end

  class << self
    def build_app_jwt
      payload = {
        # issued at time
        iat: Time.now.to_i,
        # JWT expiration time (10 minute maximum)
        exp: Time.now.to_i + (10 * 60),
        # GitHub App's identifier
        iss: GITHUB_APP_ID
      }

      JWT.encode(payload, OpenSSL::PKey::RSA.new(SECRET_KEY), "RS256")
    end

    def get_app_access_token
      uri = URI.parse("https://api.github.com/app/installations/#{GITHUB_APP_INSTALLATION_ID}/access_tokens")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.request_uri, { 'Authorization' => "Bearer #{build_app_jwt}" })
      res = http.request(req)

      JSON.parse(res.body)['token']
    end
  end

  def build_checks_body
    conclusion = @delta_coverage[:mean] >= 80 ? 'success' : 'failure'
    {
      name: "Simplecov Checks",
      head_sha: ENV['ghprbActualCommit'] || ENV['GIT_COMMIT'] || '0d19b396b771a81e0dc305cc1c380df47d2ab012',
      details_url: ENV['BUILD_URL'] || 'https://jenkins2.petalmd.com/blue/organizations/jenkins/petalmd.rails%2Fpetalmd.rails/detail/PR-6012/1/pipeline',
      status: "completed",
      completed_at: Time.now.utc.iso8601,
      conclusion: conclusion,
      output: build_output
    }
  end

  def build_output_text
    text = +"|Coverage|File|\n|---|---|\n"

    @delta_coverage[:files].each do |filename, coverage|
      text << "|#{coverage}%|#{filename}|\n"
    end
    text
  end

  def build_output
    {
      title: "Branch coverage: #{@delta_coverage[:mean]}%",
      summary: "[Build Jenkins](https://jenkins2.petalmd.com/blue/organizations/jenkins/petalmd.rails%2Fpetalmd.rails/detail/PR-6012/1/pipeline)\nTotal coverage: #{@delta_coverage[:global]}%\nBranch coverage must be ≥ 80%",
      text: build_output_text
    }
  end

  def post_check
    uri = URI.parse("https://api.github.com/repos/Bhacaz/outdated-package/check-runs")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.request_uri, { 'Authorization' => "token #{self.class.get_app_access_token}", 'Accept' => 'application/vnd.github.antiope-preview+json' })
    req.body = build_checks_body.to_json
    res = http.request(req)
    res.body
  end
end

# params[:service] = 'jenkins'
# params[:branch] = ENV['ghprbSourceBranch'] || ENV['GIT_BRANCH']
# params[:commit] = ENV['ghprbActualCommit'] || ENV['GIT_COMMIT']
# params[:pr] = ENV['ghprbPullId']
# params[:build] = ENV['BUILD_NUMBER']
# params[:root] = ENV['WORKSPACE']
# params[:build_url] = ENV['BUILD_URL']


data = SimplecovDelta.extract_delta
delta_coverage = SimplecovDelta.calculate_delta_coverage(data)
GithubApp.new(delta_coverage).post_check
