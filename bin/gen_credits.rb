#!/usr/bin/env ruby
# == Synopsis
#
# Module to assist in building the Contributors page using git commit history.
#
require 'digest/md5'
require 'fileutils'
require 'net/https'
require 'uri'
require 'cgi'
require 'date'
require 'json'
require 'set'

# Persistent string -> string map backing the lookup cache below.
#
# This used to be DBM. Ruby 3.4 dropped dbm from the standard library, so a
# script with `#!/usr/bin/env ruby` fails to even load on a machine whose PATH
# Ruby is 3.4+. JSON is core, gives identical semantics for this cache, and has
# the side benefit of being readable when the cache needs inspecting.
#
# Writes are buffered and flushed once at exit rather than on every assignment,
# since initialize() seeds several dozen entries in a row.
class CacheStore
  def initialize(path)
    @path  = "#{path}.json"
    @dirty = false
    FileUtils.mkdir_p(File.dirname(@path))
    @entries = load_entries
    at_exit { save }
  end

  def [](key)
    @entries[key]
  end

  def []=(key, value)
    value = value.to_s
    return if @entries[key] == value
    @entries[key] = value
    @dirty = true
  end

  def has_key?(key)
    @entries.has_key?(key)
  end

  def save
    return unless @dirty
    tmp = "#{@path}~"
    File.open(tmp, 'w') { |io| io << JSON.pretty_generate(@entries) }
    File.rename(tmp, @path)
    @dirty = false
  end

  private

  def load_entries
    return {} unless File.exist?(@path)
    parsed = JSON.parse(File.read(@path))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError, SystemCallError
    {}  # unreadable or corrupt cache is not fatal; it just gets rebuilt
  end
end

# Helper class to handle searching for GitHub users
# by their email address. Caches mappings to a file
# to avoid exhausting the GitHub API rate limits for
# anonymous requests.
class GitHubLookup

  def self.initialize(cache_file)
    @db = CacheStore.new(cache_file)
    # seed with some contributors that don't have an email
    # address assigned publicly in their account
    @db['1178ce2f664a6cee9a05a3e11af5d8d2'] = 'aaronbrethorst'
    @db['3b0ef5e2a5f1aa3ccf3f23a20adf8873'] = 'Hoverbear'
    @db['ff3502050b3b1b00cb6c810d5c41ffc9'] = 'bradchoate'
    @db['ee646002e51a3c83e01db85ae42187ff'] = 'dmcdougall'
    @db['85af9ad71af2dc0166b7c0c5780fa086'] = 'caldwell'
    @db['fa64968e4a3c8e20364bb92ba7511ff9'] = 'dvennink'
    @db['0669ff1e3ada91e7f1e7714f6f9a67f6'] = 'etienne'
    @db['49ed289f3de94dbcd7c10392bcc40b53'] = 'fernando82'
    @db['7b3ae2214891a47b26b4db98949c1bb0'] = 'gknops'
    @db['34820bca697fbf1598774b393c5ca4fe'] = 'whitlockjc'
    @db['ec9254734cd341f1b104d558dc4fc36a'] = 'joachimm'
    @db['09c16a631eeba332147a8d620e1369cc'] = 'muellerj'
    @db['6890db3146e20bfb99be3bc7bc3bfeec'] = 'lczekaj'
    @db['e34425c11547a48a4701c9d1720dadf8'] = 'infininight'
    @db['65efe3355478c8db96bc82f22fd3aa20'] = 'nathanieltagg'
    @db['4e89e196a1f8fa34a6bdc6d165f75e5e'] = 'Ralle'
    @db['ccc5b318408880a67eeebf0d18177fb5'] = 'rhencke'
    @db['4cf620221f7e622260f8424b8142451f'] = 'ryanmaxwell'
    @db['5780111eb4b5565816d9388b091e1057'] = 'youngrok'
    @db['1bafa0ecf5643c71e6d5dea309889d21'] = 'bobrocke'
    @db['16e62cebf0c65d7018b263d0f8be36c1'] = 'sclukey'
    @db['bee584c4bc4deac1ee91006b97a8fc53'] = 'mstarke'
    @db['578b7853042db14893ee5ec2ce043f98'] = 'yyyc514'
    @db['8838005371ab9c0b1d40f0504bf8832a'] = 'garysweaver'
    @db['1b97e22672bc2577ebbb63ef895debd4'] = 'jtmkrueger'
    @db['3413d8cb793e54a6e062391875fd2636'] = 'jacob-carlborg'
    @db['a8cb0cb6a2406ee9d85ea72f7c040697'] = 'jsuder'
    @db['af76f04ca3004be2d6b0690bd0a6ff7c'] = 'luikore'
    @db['bbe6320b030b1bb50349e4554d3169d6'] = 'AJ-Acevedo'
    @db['a734c5fda1ef1237fa6a26a64940d0b1'] = 'Dirklectisch'
    @db['7640cae93abde468b73f35d6620a9b04'] = 'caleb'
    @db['f889181fc58ccb702822b54fe3702d24'] = 'codykrieger'
    @db['571db4b87bd7d2fec3dcd5524cb7d9ae'] = 'rdwampler'
    @db['a4c0d688809489ab98a162b10c57381c'] = 'dusek'
    @db['7e9f543f0ffdb7c9a899e628fe76e7f3'] = 'jtbandes'
    @db['04581c59babdab9788e932ecb79f9617'] = 'zadr'
    @db['0ee1291a38e3c76fdfaadb2a0fa3428a'] = 'duanemoody'
    @db['71c216d75354dda636b879dfc95654fb'] = 'charliepark'
    @db['c8591aebaf7659f1ff429898345f446a'] = 'olegam'
    @db['f275727e33d63e05cc0abab1bfc41da7'] = 'sudara'
    # textmatelives fork contributors
    @db['8c31c603c339e672556eb6a80755b790'] = 'dayglojesus'  # dayglojesus@gmail.com
    @db['01209ad974dd6086f1275ba21ccf8e2e'] = 'dayglojesus'  # dayglojesus@users.noreply.github.com
  end

  # Resolve a commit author's GitHub login. The legacy "search user by
  # email address" API is gone, so we look up the commit by SHA via the
  # GitHub REST API (repos/{repo}/commits/{sha}) and read author.login.
  # Cache by MD5(email) so subsequent commits with the same email reuse
  # the result. Returns nil (and caches "") on any failure, retaining a
  # marker that we already tried so we don't refetch on every build.
  def self.user_by_email(email, repo=nil, sha=nil)
    emailhash = Digest::MD5.hexdigest(email)
    if @db.has_key?(emailhash)
      cached = @db[emailhash].to_s
      return cached.empty? ? nil : cached if @db.has_key?("tried:#{emailhash}") || !cached.empty?
    end

    return nil unless repo && sha

    url = "https://api.github.com/repos/#{repo}/commits/#{sha}"
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri, {
      'User-Agent' => 'textmatelives-build',
      'Accept'     => 'application/vnd.github+json'
    })
    request['Authorization'] = "Bearer #{ENV['GITHUB_TOKEN']}" if ENV['GITHUB_TOKEN'] && !ENV['GITHUB_TOKEN'].empty?

    begin
      response = http.request(request)
    rescue StandardError
      return nil  # network error: don't poison cache, retry next build
    end

    @db["tried:#{emailhash}"] = '1'

    unless response.code == '200'
      @db[emailhash] = ''
      return nil
    end

    data = JSON.parse(response.body) rescue nil
    login = data && data['author'].is_a?(Hash) ? data['author']['login'] : nil
    @db[emailhash] = login.to_s
    return login && !login.empty? ? login : nil
  end

end

def detect_github_repo
  origin = `git remote get-url origin 2>/dev/null`.strip
  match = origin.match(%r{github\.com[:/]([^/]+/[^/.]+?)(?:\.git)?\z})
  match ? match[1] : nil
end

# Show only contributions that have actually made it onto the project's
# primary branch. Without this, a build from a feature branch would
# list its in-flight commits as published contributions.
def detect_log_ref
  %w[origin/main main HEAD].find { |r| system("git rev-parse --verify --quiet #{r} >/dev/null") } || 'HEAD'
end

def generate_credits(cache_file, warn=false)
  GitHubLookup.initialize(cache_file)
  did_warn_db = Set.new
  repo = detect_github_repo
  log_ref = detect_log_ref

  # use git's log command to pull out basic info:
  # git hash, author name, email address, author date, commit summary
  cmd = %Q{git log #{log_ref} -z --date=iso --pretty=format:"%H%n%an%n%ae%n%ad%n%s%n%B"}

  `#{cmd}`.force_encoding('UTF-8').split(/\x00/).each {|commit|
    fields = commit.split(/\n/, 6).map { |f| f.force_encoding('UTF-8') }

    # omit commits from Allan; he gets enough credit already ;)
    if fields[1] != 'Allan Odgaard' then
      # hash email address for referencing Gravatar userpics
      emailhash = Digest::MD5.hexdigest(fields[2])

      # escape user-supplied bits like name and subject
      hash = fields[0]
      name = CGI.escapeHTML(fields[1])
      # locate the GitHub login for the author's email address
      user = GitHubLookup.user_by_email(fields[2], repo, hash)
      date = DateTime.parse(fields[3])
      subject = CGI.escapeHTML(fields[4])
      body = CGI.escapeHTML(fields[5].sub(fields[4], '').sub(/[\s\x00]+$/, '').sub(/^[\s\x00]+/, ''))
      # Prefer the per-username GitHub avatar so the same person renders
      # identically regardless of which commit-author email they used
      # (e.g. real email vs {login}@users.noreply.github.com from
      # GitHub-UI PR-merge commits). Fall back to Gravatar+identicon for
      # unknowns.
      userpic = if user && !user.empty?
        "https://github.com/#{user}.png?size=48"
      else
        "https://www.gravatar.com/avatar/#{emailhash}?s=48&amp;d=identicon"
      end

      # if we have a github username, populate a link to their
      # profile.
      if !user || user == ''
        user = nil

        key = "#{name} <#{fields[2]}>"
        unless did_warn_db.include?(key)
          did_warn_db.add(key)
          if warn
            STDERR << "WARNING: failed to find GitHub user for #{key}\n";
          end
        end
      end

      yield(hash, name, subject, body, userpic, date, user)
    end
  }
end

__END__
# Contributions

See [commits at GitHub][1].

<table width="100%">
    <tr>
        <th width="20%">Author</th>
        <th width="60%">Contribution</th>
        <th width="20%">Date</th>
    </tr>
<%
require 'bin/gen_credits'
credits = generate_credits(File.expand_path('~/Library/Caches/com.macromates.TextMate/githubcredits'))
%>
<%= credits %>
</table>

[1]: https://github.com/textmate/textmate/commits/master
