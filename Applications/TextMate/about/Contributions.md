Title: Contributions
CSS: css/contributions.css

<h1 id="contributions">Contributions</h1>

<p class="contrib-intro">
  People who have committed to TextMate, most prolific first.
  See <a href="https://github.com/textmatelives/textmate/commits/main">the full commit log at GitHub</a>.
</p>

<div>
<%# wrapping div keeps the ERB out of the markdown parser's way %>
<%
require File.join(File.dirname(__FILE__), 'bin/gen_credits')
total_authors = 0
total_commits = 0
rows = ''
generate_authors(File.expand_path('~/Library/Caches/com.macromates.TextMate/githubcredits'), warn) do |a|
  total_authors += 1
  total_commits += a[:commits]
  span = if a[:first].strftime('%Y') == a[:last].strftime('%Y')
    a[:last].strftime('%Y')
  else
    "#{a[:first].strftime('%Y')}–#{a[:last].strftime('%Y')}"
  end
  name = a[:user] ? %Q{<a href="https://github.com/#{a[:user]}">#{a[:name]}</a>} : a[:name]
  handle = a[:user] ? %Q{<span class="contrib-handle">@#{a[:user]}</span>} : ''
  plural = a[:commits] == 1 ? 'commit' : 'commits'
  rows << <<~ROW
    <li class="contrib">
      <img class="contrib-avatar" src="#{a[:userpic]}" height="48" width="48" alt="">
      <div class="contrib-body">
        <div class="contrib-name">#{name} #{handle}</div>
        <div class="contrib-meta">#{a[:commits]} #{plural} · #{span}</div>
      </div>
    </li>
  ROW
end
%>
<p class="contrib-summary"><%= total_authors %> contributors · <%= total_commits %> commits</p>
<ol class="contrib-list">
<%= rows %>
</ol>
</div>
