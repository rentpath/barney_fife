module BarneyFife
  module Rubocop
    class RoundUp
      attr_accessor :pull_request_number, :response, :response_body, :api, :client, :owner, :repo

      SHA_REGEX = /[a-f0-9]{40,40}\//

      def self.call(pull_request_number, owner, repo, tmpdir)
        round = new(pull_request_number, owner, repo)
        round.gather_pull_request
        round.download_files(tmpdir)
      end

      def initialize(pull_request_number, owner, repo)
        @pull_request_number = pull_request_number
        @owner = owner
        @repo = repo
        @client = Octokit::Client.new access_token: ENV['GITHUB_AUTH_TOKEN']
        @api = Faraday.new 'https://api.github.com' do |conn|
          conn.use Faraday::Request::BasicAuthentication, ENV['GITHUB_AUTH_TOKEN'], 'x-oauth-basic'
          conn.request :json

          conn.response :json, :content_type => /\bjson$/
          conn.use :instrumentation
          conn.adapter Faraday.default_adapter
        end
      end

      def gather_commits
        # GET /repos/:owner/:repo/pulls/:number/commits
        res = @api.get "/repos/#{owner}/#{repo}/pulls/#{pull_request_number}/commits"
        res.body.map { |i| Hashie::Mash.new(i) }
      end

      #gather all files from github PR files modified/added list
      def gather_pull_request
        @response_body ||= request_pr_files
      end

      def request_pr_files
        @response = @api.get "/repos/#{owner}/#{repo}/pulls/#{pull_request_number}/files"
        response.body.map { |item| Hashie::Mash.new(item) }
      end

      def files_modified
        @files_modified ||= response_body
      end

      def split_on_sha(url)
        url.split(SHA_REGEX)[1]
      end

      def extract_sha(url)
        url[SHA_REGEX]
      end

      def extract_repo(url)
        url.split('https://github.com/')[1].split('/raw')[0]
      end

      def get_file(content_url)
        Base64.decode64(api.get(content_url).body['content'])
      end

      def dirs_to_create(shortname)
        shortname.split(File::SEPARATOR)[0..-2].join(File::SEPARATOR)
      end

      def download_files(tmp_rubodir, files = files_modified)
        files.peach do |file|
          raw_url = file.raw_url
          content_url = file.contents_url
          file_shortname = split_on_sha(raw_url)
          content_url = content_url.split('https://api.github.com')[1]
          necessary_dir = dirs_to_create(file_shortname)
          filename = file_shortname.split(File::SEPARATOR)[-1]
          file_dir = File.join(tmp_rubodir, necessary_dir)

          unless Dir.exists?(file_dir)
            FileUtils.mkdir_p(file_dir)
          end

          File.open(File.join(file_dir, filename), 'wb') do |wfile|
            wfile.write(get_file(content_url))
          end
        end
      end
    end
  end
end
