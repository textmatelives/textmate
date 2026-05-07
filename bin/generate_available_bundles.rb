#!/usr/bin/env ruby
# Generates Applications/TextMate/resources/AvailableBundles.plist from
# MISSING_BUNDLES_TO_ADD.md plus a hardcoded branch-ref map.
#
# Output schema mirrors the existing Made of Code seed entry:
#   <dict>
#     <key>uuid</key><string>UUID</string>
#     <key>name</key><string>Name</string>
#     <key>url</key><string>https://github.com/dayglojesus/repo</string>
#     <key>ref</key><string>master|remove-legacy-ruby|python3-port|arm64-binaries</string>
#     <key>autoUpdate</key><true/>
#     <key>category</key><string>Build|Languages|SCM|Other|Themes|Testing</string>
#   </dict>

require 'pathname'

ROOT   = Pathname(File.expand_path('..', __dir__))
SOURCE = ROOT.join('MISSING_BUNDLES_TO_ADD.md')
OUTPUT = ROOT.join('Applications/TextMate/resources/AvailableBundles.plist')

# Phase 3 + manual deferrals — these UUIDs/repos must NOT appear in the plist
# even if they were ever in MISSING_BUNDLES_TO_ADD.md (defense in depth — the
# .md should already exclude them).
DEFERRED_UUIDS = %w[
  D619CB94-53ED-41C5-963B-401492CE2602
  6ED4A84B-3953-408E-B09B-6BF38C73D958
  AC7585E9-775D-4181-B476-4CC3CEE75D39
  F80D3822-6EE8-11D9-BF2D-000D93589AF6
].freeze

# Branch ref per fork (keyed by dayglojesus fork name without owner prefix).
# Default is 'master' for any fork not listed here.
ARM64_BRANCH = %w[
  latex.tmbundle
  scala.tmbundle
].freeze

PY3_BRANCH = %w[
  ant.tmbundle
  txt2tags.tmbundle
  mathematica-tmbundle
  pdb.tmbundle
  scons.tmbundle
  unicode.tmbundle
].freeze

# Phase 1 ruby18 bundles minus deferrals minus cross-phase merges.
# Exact list pinned by audit (sorted).
RUBY18_BRANCH = %w[
  Julia.tmbundle
  ada.tmbundle
  applescript.tmbundle
  arduino.tmbundle
  cmake.tmbundle
  elixir-tmbundle
  fortran.tmbundle
  golang.tmbundle
  haskell.tmbundle
  less.tmbundle
  licenses.tmbundle
  man-pages.tmbundle
  matlab.tmbundle
  maude.tmbundle
  maven.tmbundle
  mips.tmbundle
  nim.tmbundle
  ninja.tmbundle
  processing.tmbundle
  prolog.tmbundle
  python-django.tmbundle
  r.tmbundle
  regularexpressions.tmbundle
  rspec.tmbundle
  ruby-on-rails-tmbundle
  rust.tmbundle
  scheme.tmbundle
  swift.tmbundle
  tads3.tmbundle
  textile.tmbundle
  vagrant.tmbundle
].freeze

# Upstream basename → dayglojesus fork basename (collision-rename overrides).
FORK_RENAMES = {
  'rspec-tmbundle' => 'rspec.tmbundle',
}.freeze

ENTRY_RE = /
  ^- \s\*\*(?<name>[^*]+)\*\* \s—\s `(?<uuid>[0-9A-Fa-f-]{36})` \s—\s _(?<author>[^_]+)_ \s*\n
  \s+- \shttps?:\/\/github\.com\/(?<owner>[^\/]+)\/(?<repo>[^\s]+) \s*\n
  (?:\s+- \s(?<desc>[^\n]+) \s*\n)?
/x

def parse_md
  text = SOURCE.read
  current_category = nil
  entries = []

  text.each_line.with_index do |line, i|
    if (m = line.match(/\A##\s+([A-Za-z]+)\s+\(\d+\)/))
      current_category = m[1]
      next
    end
  end

  # Split by category sections, then parse entries inside each.
  sections = text.split(/^## /m)
  sections.shift  # drop preamble

  sections.each do |section|
    header, *_ = section.lines
    if (m = header.match(/\A([A-Za-z]+)\s+\(\d+\)/))
      cat = m[1]
      section.scan(ENTRY_RE) do |name, uuid, _author, _owner, repo, desc|
        repo = repo.strip.sub(/\.git\z/, '')
        desc = desc&.strip
        desc = nil if desc == '(no description)'
        entries << {
          name:     name.strip,
          uuid:     uuid,
          repo:     repo,
          category: cat,
          summary:  desc,
        }
      end
    end
  end

  entries
end

def fork_name(upstream_repo)
  FORK_RENAMES[upstream_repo] || upstream_repo
end

def branch_for(fork)
  return 'arm64-binaries'     if ARM64_BRANCH.include?(fork)
  return 'python3-port'       if PY3_BRANCH.include?(fork)
  return 'remove-legacy-ruby' if RUBY18_BRANCH.include?(fork)
  'master'
end

def render_entry(uuid:, name:, fork:, ref:, category:, summary:)
  esc = ->(s) { s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;') }
  url = "https://github.com/dayglojesus/#{fork}"
  desc_line = summary && !summary.empty? ?
    "\n\t\t\t<key>description</key><string>#{esc.call(summary)}</string>" :
    ''
  <<~XML.chomp
		<dict>
			<key>uuid</key><string>#{uuid}</string>
			<key>name</key><string>#{esc.call(name)}</string>
			<key>url</key><string>#{url}</string>
			<key>ref</key><string>#{ref}</string>
			<key>autoUpdate</key><true/>
			<key>category</key><string>#{category}</string>#{desc_line}
		</dict>
  XML
end

def render_plist(entries)
  body = entries.map { |e|
    render_entry(
      uuid:     e[:uuid],
      name:     e[:name],
      fork:     e[:fork],
      ref:      e[:ref],
      category: e[:category],
      summary:  e[:summary],
    )
  }.join("\n")
  <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>schemaVersion</key>
    \t<integer>1</integer>
    \t<key>bundles</key>
    \t<array>
    #{body}
    \t</array>
    </dict>
    </plist>
  XML
end

all_entries = parse_md.reject { |e| DEFERRED_UUIDS.include?(e[:uuid]) }
all_entries.map! do |e|
  fork = fork_name(e[:repo])
  ref  = branch_for(fork)
  e.merge(fork: fork, ref: ref)
end

# Sanity counts.
by_category = all_entries.group_by { |e| e[:category] }
total = all_entries.size
puts "Generated entries by category:"
by_category.sort.each { |cat, list| puts "  #{cat.ljust(12)} #{list.size}" }
puts "  #{'TOTAL'.ljust(12)} #{total}"

by_branch = all_entries.group_by { |e| e[:ref] }
puts "Generated entries by branch ref:"
by_branch.sort.each { |ref, list| puts "  #{ref.ljust(20)} #{list.size}" }

# Write output.
OUTPUT.write(render_plist(all_entries))
puts "Wrote #{OUTPUT}"

# Plist lint.
unless system('plutil', '-lint', OUTPUT.to_s)
  abort "plutil -lint failed for #{OUTPUT}"
end
