#!/usr/bin/env ruby
# frozen_string_literal: true

# Build Support/BundleFileTypeIndex.plist by fetching grammar files from
# GitHub. Reads catalogue from sibling Support/DefaultBundles.plist and
# Support/AvailableBundles.plist, plus the mandatory-bundle list pulled
# from textmatelives/textmate@main:Frameworks/BundlesManager/src/MandatoryBundles.h
# (mandatory bundles still live in the app — chicken-and-egg).
#
# For every catalogue bundle, GET /repos/<owner>/<repo>/contents/Syntaxes
# is used to discover grammar files; each grammar's raw content is fetched
# from raw.githubusercontent.com (download_url field) and parsed for
# fileTypes + scopeName. Priority/collision resolution:
# mandatory > shipped > available; same-tier ties must be listed in
# COLLISION_TIEBREAK.
#
# Authentication: requires the `gh` CLI authenticated against an account
# with read access to all textmatelives bundle repos. Unauthenticated
# GitHub API is 60 reqs/hr — not enough for 149 bundles. In CI use
# `GITHUB_TOKEN` (5000 reqs/hr); locally run `gh auth login` once.
#
# Coverage: any catalogue bundle that contributes zero extensions is
# warned at the end. Bundles that legitimately have no Syntaxes/ (themes,
# pure-snippet bundles) are reported the same way — the human reviewer
# decides whether each zero-contributor is expected.
#
# Platform: macOS or Linux. Uses `plutil` if available (macOS) for binary
# plist conversion; falls back to assuming XML on Linux.
#
# Run:
#   ruby Support/build_filetype_index.rb

require 'rexml/document'
require 'json'
require 'open3'
require 'base64'
require 'set'

# ----------------------------------------------------------------------------
# Hand-curated tiebreaks for extensions claimed by multiple bundles at the
# same priority tier. Keys are lowercase extensions; values are bundle UUIDs.
COLLISION_TIEBREAK = {
  # Prefer C over C++/Objective-C for .h
  'h'    => '4675A940-6227-11D9-BFB1-000D93589AF6',
  'jsp'  => '4677FEB2-6227-11D9-BFB1-000D93589AF6', # Java over XML
  'pde'  => 'DC9271C5-8267-4C5F-93A9-3E3FFC741BEA', # Processing over Arduino
  'fs'   => 'A29B280D-8D4C-4416-AC5A-97F50669603A', # F Sharp over Forth
  'l'    => '408054F2-BF56-439E-B52F-5EC62ED0A849', # Lex/Flex over Lisp
  's'    => '402D341A-6BE4-11D9-AEC0-0011242E4184', # MIPS Assembler over R
  'r'    => 'B29D7850-6E70-11D9-A369-000D93B3A10E', # R over Rez
  'sass' => '176253C8-5D97-4C20-AA34-3BE8BC73FBC9'  # Ruby Sass over Ruby Haml
}.freeze
# ----------------------------------------------------------------------------

PRIORITY_MANDATORY = 3
PRIORITY_SHIPPED   = 2
PRIORITY_AVAILABLE = 1
PRIORITY_UNKNOWN   = 0

MANDATORY_SOURCE_REPO = 'textmatelives/textmate'
MANDATORY_SOURCE_REF  = 'main'
MANDATORY_SOURCE_PATH = 'Frameworks/BundlesManager/src/MandatoryBundles.h'

# Shell-out to gh api. Returns parsed JSON (Array/Hash) or nil on 404 /
# error. Errors other than 404 are surfaced as warnings.
def gh_api(path)
  out, err, status = Open3.capture3('gh', 'api', path)
  unless status.success?
    return nil if err.include?('"message":"Not Found"') || err.include?('HTTP 404')
    warn "WARN: gh api #{path}: #{err.strip}"
    return nil
  end
  JSON.parse(out)
rescue JSON::ParserError => e
  warn "WARN: gh api #{path} JSON parse: #{e.message}"
  nil
end

# Fetch raw bytes from a URL (used for download_url returned by the
# /contents/ endpoint — already points at raw.githubusercontent.com).
def fetch_raw(url)
  out, err, status = Open3.capture3('curl', '--silent', '--show-error', '--fail', '--location', url)
  return out if status.success?
  warn "WARN: curl #{url}: #{err.strip}"
  nil
end

def parse_plist_xml(xml_str)
  doc = REXML::Document.new(xml_str)
  root = doc.root.elements['dict'] || doc.root.elements['array']
  plist_value(root)
end

def plist_value(el)
  case el.name
  when 'dict'
    dict = {}
    children = el.elements.to_a
    i = 0
    while i < children.length
      k = children[i]
      v = children[i + 1]
      dict[k.text] = plist_value(v) if k.name == 'key' && v
      i += 2
    end
    dict
  when 'array'
    el.elements.map { |c| plist_value(c) }
  when 'string'
    el.text || ''
  when 'integer'
    el.text.to_i
  when 'real'
    el.text.to_f
  when 'true'
    true
  when 'false'
    false
  else
    el.text
  end
end

def plutil_available?
  @plutil_available = system('which plutil > /dev/null 2>&1') if @plutil_available.nil?
  @plutil_available
end

# Convert any local .plist file (XML or binary) to a Ruby Hash. Prefers
# plutil; falls back to direct XML parse on systems without it.
def parse_local_plist(path)
  if plutil_available?
    out, err, status = Open3.capture3('plutil', '-convert', 'xml1', '-o', '-', path)
    raise "plutil failed for #{path}: #{err}" unless status.success?
    parse_plist_xml(out)
  else
    parse_plist_xml(File.read(path))
  end
end

# Parse a grammar file content. Returns Hash with fileTypes + scopeName,
# or nil on parse failure. Handles XML plist, binary plist, and JSON
# tmLanguage. plutil reads any plist flavor from stdin and emits XML.
def parse_grammar(content, filename)
  if filename.end_with?('.json')
    JSON.parse(content)
  elsif plutil_available?
    out, _err, status = Open3.capture3('plutil', '-convert', 'xml1', '-o', '-', '-', stdin_data: content)
    return nil unless status.success?
    parse_plist_xml(out)
  else
    parse_plist_xml(content)
  end
rescue StandardError => e
  warn "WARN: grammar parse failed for #{filename}: #{e.message}"
  nil
end

def parse_github_url(url)
  return nil if url.nil? || url.empty?
  m = url.match(%r{\Ahttps?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?\z})
  return nil unless m
  [m[1], m[2]]
end

def fetch_mandatory_bundles
  resp = gh_api("repos/#{MANDATORY_SOURCE_REPO}/contents/#{MANDATORY_SOURCE_PATH}?ref=#{MANDATORY_SOURCE_REF}")
  unless resp.is_a?(Hash) && resp['content']
    warn "WARN: could not fetch MandatoryBundles.h from #{MANDATORY_SOURCE_REPO}@#{MANDATORY_SOURCE_REF}; mandatory tier will be empty"
    return []
  end
  header = Base64.decode64(resp['content'])
  seen = Set.new
  result = []
  header.scan(/\{\s*"([0-9A-Fa-f-]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([0-9a-fA-F]{40})"\s*,/m).each do |uuid, name, url, sha|
    owner, repo = parse_github_url(url)
    next unless owner
    uuid_up = uuid.upcase
    next if seen.include?(uuid_up)
    seen << uuid_up
    result << { uuid: uuid_up, name: name, owner: owner, repo: repo, ref: sha, priority: PRIORITY_MANDATORY }
  end
  result
end

def catalogue_bundles
  result = fetch_mandatory_bundles
  seen_uuids = result.map { |b| b[:uuid] }.to_set

  support_dir = __dir__
  [
    ['DefaultBundles.plist',   PRIORITY_SHIPPED],
    ['AvailableBundles.plist', PRIORITY_AVAILABLE]
  ].each do |fname, prio|
    path = File.join(support_dir, fname)
    next unless File.exist?(path)
    data = parse_local_plist(path)
    (data['bundles'] || []).each do |b|
      uuid_up = b['uuid'].to_s.upcase
      next if uuid_up.empty?
      next if seen_uuids.include?(uuid_up)
      owner, repo = parse_github_url(b['url'])
      next unless owner
      seen_uuids << uuid_up
      result << { uuid: uuid_up, name: b['name'].to_s, owner: owner, repo: repo, ref: b['ref'].to_s, priority: prio }
    end
  end

  result
end

def collect_remote_bundle(bundle)
  path = "repos/#{bundle[:owner]}/#{bundle[:repo]}/contents/Syntaxes?ref=#{bundle[:ref]}"
  contents = gh_api(path)
  return [] unless contents.is_a?(Array)

  records = []
  contents.each do |entry|
    fname = entry['name'].to_s
    next unless fname =~ /\.(plist|tmLanguage|tmLanguage\.json)\z/

    raw = fetch_raw(entry['download_url'].to_s)
    next unless raw

    grammar = parse_grammar(raw, fname)
    next unless grammar.is_a?(Hash)

    scope = grammar['scopeName'].to_s
    (grammar['fileTypes'] || []).each do |ft|
      next if ft.nil? || ft.to_s.strip.empty?
      records << {
        ext:        ft.to_s.downcase,
        bundleUUID: bundle[:uuid],
        bundleName: bundle[:name],
        scopeName:  scope
      }
    end
  end
  records
end

def resolve(by_ext, priority_by_uuid)
  winners = {}
  conflicts = []

  by_ext.each do |ext, recs|
    uniq = recs.uniq { |r| r[:bundleUUID] }
    if uniq.length == 1
      winners[ext] = uniq[0]
      next
    end

    by_prio = uniq.group_by { |r| priority_by_uuid[r[:bundleUUID]] || PRIORITY_UNKNOWN }
    top = by_prio.keys.max
    top_recs = by_prio[top]

    if top_recs.length == 1
      winners[ext] = top_recs[0]
      next
    end

    tb = COLLISION_TIEBREAK[ext]
    if tb
      tb_up = tb.upcase
      cand_uuids = top_recs.map { |r| r[:bundleUUID] }
      unless cand_uuids.include?(tb_up)
        raise "COLLISION_TIEBREAK['#{ext}'] = #{tb} is not among candidates " \
              "#{cand_uuids.inspect}. Fix the constant."
      end
      winners[ext] = top_recs.find { |r| r[:bundleUUID] == tb_up }
    else
      conflicts << [ext, top_recs]
    end
  end

  [winners, conflicts]
end

def xml_escape(str)
  str.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
end

def render_plist(winners)
  body = +<<~HEAD
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>version</key>
    \t<integer>1</integer>
    \t<key>byExtension</key>
    \t<dict>
  HEAD
  winners.keys.sort.each do |ext|
    rec = winners[ext]
    body << "\t\t<key>#{xml_escape(ext)}</key>\n"
    body << "\t\t<dict>\n"
    body << "\t\t\t<key>bundleName</key><string>#{xml_escape(rec[:bundleName])}</string>\n"
    body << "\t\t\t<key>bundleUUID</key><string>#{xml_escape(rec[:bundleUUID])}</string>\n"
    body << "\t\t</dict>\n"
  end
  body << "\t</dict>\n</dict>\n</plist>\n"
  body
end

def main
  _out, _err, status = Open3.capture3('gh', 'auth', 'status')
  unless status.success?
    warn 'ERROR: `gh` CLI is not authenticated. Run `gh auth login` first.'
    warn '       Unauthenticated GitHub API allows 60 reqs/hr, well under the'
    warn '       ~300-500 calls needed to index all catalogue bundles.'
    exit 1
  end

  bundles = catalogue_bundles
  if bundles.empty?
    warn 'ERROR: No bundles found in catalogue (MandatoryBundles.h + Default/Available plists).'
    exit 1
  end
  puts "Catalogue: #{bundles.length} bundles to inspect."

  records = []
  contributing = Set.new
  bundles.each_with_index do |b, i|
    label = "[#{i + 1}/#{bundles.length}] #{b[:name]} (#{b[:owner]}/#{b[:repo]}@#{b[:ref][0, 7]})"
    recs = collect_remote_bundle(b)
    records.concat(recs)
    if recs.any?
      contributing << b[:uuid]
      puts "#{label}: #{recs.length} ext(s)"
    else
      puts "#{label}: no grammars"
    end
  end

  priority_by_uuid = bundles.each_with_object({}) { |b, h| h[b[:uuid]] = b[:priority] }

  by_ext = records.group_by { |r| r[:ext] }
  winners, conflicts = resolve(by_ext, priority_by_uuid)

  unless conflicts.empty?
    warn 'ERROR: Same-tier collisions detected. Add tiebreaks to COLLISION_TIEBREAK.'
    conflicts.each do |ext, recs|
      warn "  .#{ext}:"
      recs.each do |r|
        warn "    - #{r[:bundleName]} (#{r[:bundleUUID]}) scope=#{r[:scopeName]}"
      end
    end
    exit 2
  end

  out_path = File.join(__dir__, 'BundleFileTypeIndex.plist')
  File.write(out_path, render_plist(winners))

  zero_contributors = bundles.reject { |b| contributing.include?(b[:uuid]) }

  puts ''
  puts "Wrote #{out_path}"
  puts "  #{winners.length} extensions from #{contributing.length}/#{bundles.length} bundles"

  if zero_contributors.any?
    puts ''
    puts "Bundles that contributed zero extensions (#{zero_contributors.length}):"
    puts '  (snippet/theme bundles legitimately have no Syntaxes/. Review the list;'
    puts '  unexpected entries here usually mean a fetch failed or a grammar is broken.)'
    zero_contributors.sort_by { |b| b[:name] }.each do |b|
      tier =
        case b[:priority]
        when PRIORITY_MANDATORY then 'mandatory'
        when PRIORITY_SHIPPED   then 'default'
        when PRIORITY_AVAILABLE then 'available'
        else                         'unknown'
        end
      puts "  - [#{tier}] #{b[:name]} (#{b[:owner]}/#{b[:repo]})"
    end
  end
end

main if $PROGRAM_NAME == __FILE__
