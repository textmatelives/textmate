#!/usr/bin/env ruby
# frozen_string_literal: true

# Fill missing `description` fields in Support/DefaultBundles.plist and
# Support/AvailableBundles.plist by fetching each bundle's own info.plist
# from GitHub via gh api.
#
# The catalogue keeps a normalized form of info.plist's description —
# HTML stripped, anchor URLs flattened to "TEXT (URL)" so an NSTextField
# can render it as plain text. By default this script ONLY fills entries
# whose description is missing or empty; pass --refresh to also overwrite
# existing entries from the upstream info.plist.
#
# Authentication: requires the `gh` CLI authenticated (5000 reqs/hr).
# Unauthenticated is 60 reqs/hr — not enough for ~150 bundles.
#
# Run:
#   ruby Support/backfill_descriptions.rb            # backfill missing
#   ruby Support/backfill_descriptions.rb --refresh  # refresh all

require 'rexml/document'
require 'json'
require 'open3'

SOURCE_PLISTS = %w[DefaultBundles.plist AvailableBundles.plist].freeze

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

def fetch_raw(url)
  out, err, status = Open3.capture3('curl', '--silent', '--show-error', '--fail', '--location', url)
  return out if status.success?
  warn "WARN: curl #{url}: #{err.strip}"
  nil
end

def parse_github_url(url)
  return nil if url.nil? || url.empty?
  m = url.match(%r{\Ahttps?://github\.com/([^/]+)/([^/]+?)(?:\.git)?/?\z})
  return nil unless m
  [m[1], m[2]]
end

# REXML-based parser for the bundle's info.plist (XML format). Returns the
# description string or nil. We only need one key, so don't bother walking
# the full tree.
def extract_description(xml_str)
  doc = REXML::Document.new(xml_str)
  root_dict = doc.root.elements['dict']
  return nil unless root_dict
  children = root_dict.elements.to_a
  i = 0
  while i < children.length
    k = children[i]
    v = children[i + 1]
    if k.name == 'key' && k.text == 'description' && v && v.name == 'string'
      return v.text || ''
    end
    i += 2
  end
  nil
rescue REXML::ParseException => e
  warn "WARN: info.plist parse failed: #{e.message}"
  nil
end

# Normalize HTML-ish description from a bundle's info.plist into the plain
# form the catalogue uses. Examples:
#   <a href="http://x" title="y">Foo</a> is a thing.
#     -> Foo (http://x) is a thing.
#   <a href="http://x">Bar</a>
#     -> Bar (http://x)
#   Plain text <b>bold</b> &amp; thing
#     -> Plain text bold & thing
def normalize_description(raw)
  return '' if raw.nil?
  s = raw.dup

  # Flatten anchors. Preserve TEXT, append (URL).
  s = s.gsub(/<a\s+[^>]*href="([^"]+)"[^>]*>(.*?)<\/a>/im) do
    text = Regexp.last_match(2).strip
    url  = Regexp.last_match(1).strip
    "#{text} (#{url})"
  end

  # Strip every other tag.
  s = s.gsub(/<[^>]+>/, '')

  # Decode the HTML entities that actually show up in tmbundle descriptions.
  {
    '&amp;'  => '&',
    '&lt;'   => '<',
    '&gt;'   => '>',
    '&quot;' => '"',
    '&apos;' => "'",
    '&#39;'  => "'"
  }.each { |k, v| s = s.gsub(k, v) }

  s.strip
end

def fetch_description_for(url, ref)
  owner, repo = parse_github_url(url)
  return nil unless owner

  info = gh_api("repos/#{owner}/#{repo}/contents/info.plist?ref=#{ref || 'main'}")
  return nil unless info.is_a?(Hash) && info['download_url']

  raw = fetch_raw(info['download_url'])
  return nil unless raw

  desc = extract_description(raw)
  desc && !desc.strip.empty? ? normalize_description(desc) : nil
end

# Read an XML plist via plutil. Returns root dict.
def parse_local_plist(path)
  out, err, status = Open3.capture3('plutil', '-convert', 'xml1', '-o', '-', path)
  raise "plutil failed for #{path}: #{err}" unless status.success?
  doc = REXML::Document.new(out)
  root = doc.root.elements['dict']
  raise "no root dict in #{path}" unless root
  [doc, root]
end

# Find the <string> element for the `description` key inside an entry dict.
# Returns [element, parent_dict, key_element] — element may be nil if absent.
def find_description_node(entry_dict)
  children = entry_dict.elements.to_a
  i = 0
  while i < children.length
    k = children[i]
    v = children[i + 1]
    return [v, k] if k.name == 'key' && k.text == 'description'
    i += 2
  end
  [nil, nil]
end

def get_string_value(entry_dict, key_name)
  children = entry_dict.elements.to_a
  i = 0
  while i < children.length
    k = children[i]
    v = children[i + 1]
    return v.text if k.name == 'key' && k.text == key_name && v && v.name == 'string'
    i += 2
  end
  nil
end

def insert_description(entry_dict, value)
  # Insert <key>description</key><string>VALUE</string> at the end of the
  # entry's children, before the closing </dict>. REXML appends naturally.
  k = REXML::Element.new('key')
  k.text = 'description'
  s = REXML::Element.new('string')
  s.text = value
  entry_dict.add_element(k)
  entry_dict.add_element(s)
end

def process_plist(path, refresh:)
  doc, root = parse_local_plist(path)

  bundles_array = nil
  children = root.elements.to_a
  i = 0
  while i < children.length
    k = children[i]
    v = children[i + 1]
    if k.name == 'key' && k.text == 'bundles' && v && v.name == 'array'
      bundles_array = v
      break
    end
    i += 2
  end
  unless bundles_array
    warn "ERROR: no `bundles` array in #{path}"
    return false
  end

  changed = 0
  skipped = 0
  failed  = 0
  bundles_array.elements.each_with_index do |entry, idx|
    next unless entry.name == 'dict'

    name = get_string_value(entry, 'name') || "<#{idx}>"
    url  = get_string_value(entry, 'url')
    ref  = get_string_value(entry, 'ref')

    desc_node, _key_node = find_description_node(entry)
    existing = desc_node ? (desc_node.text || '') : ''

    if existing.strip.length > 0 && !refresh
      skipped += 1
      next
    end

    fetched = fetch_description_for(url, ref)
    if fetched.nil? || fetched.empty?
      warn "  [no desc] #{name} (#{url})"
      failed += 1
      next
    end

    if desc_node
      desc_node.text = fetched
    else
      insert_description(entry, fetched)
    end
    puts "  [set]     #{name}: #{fetched[0, 90]}#{fetched.length > 90 ? '…' : ''}"
    changed += 1
  end

  if changed > 0
    formatter = REXML::Formatters::Default.new
    File.open(path, 'w') do |f|
      formatter.write(doc, f)
      f.write("\n") unless doc.to_s.end_with?("\n")
    end
    # Normalize via plutil so we keep the canonical Apple plist format
    # (tabs, DOCTYPE, etc).
    `plutil -convert xml1 '#{path}'`
  end

  puts "#{path}: set=#{changed} skipped=#{skipped} failed=#{failed}"
  true
end

def main
  refresh = ARGV.include?('--refresh')

  _out, _err, status = Open3.capture3('gh', 'auth', 'status')
  unless status.success?
    warn 'ERROR: `gh` CLI is not authenticated. Run `gh auth login` first.'
    exit 1
  end

  support_dir = __dir__
  SOURCE_PLISTS.each do |name|
    path = File.join(support_dir, name)
    next unless File.exist?(path)
    puts "==> #{name}"
    process_plist(path, refresh: refresh)
  end
end

main if $PROGRAM_NAME == __FILE__
