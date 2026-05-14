#!/usr/bin/env ruby
# frozen_string_literal: true

# Build BundleFileTypeIndex.plist from the dayglojesus bundle source tree.
#
# Walks each *.tmbundle/ directory, reads info.plist (uuid + name) and any
# Syntaxes/*.{plist,tmLanguage,tmLanguage.json} files for fileTypes + scopeName.
# Collates extension -> bundle, applying mandatory > shipped > available
# priority. Same-tier collisions abort unless listed in COLLISION_TIEBREAK.
#
# Run:
#   BUNDLES_DIR=~/src/github.com/dayglojesus/bundles \
#   BUNDLE_SUPPORT_DIR=~/src/github.com/dayglojesus/bundle-support.tmbundle \
#   ruby bin/build_filetype_index.rb

require 'rexml/document'
require 'json'
require 'open3'
require 'set'
require 'fileutils'

# ----------------------------------------------------------------------------
# Hand-curated tiebreaks for extensions claimed by multiple bundles at the
# same priority tier. Add entries here as collisions are discovered. Keys are
# lowercase extensions; values are bundle UUIDs.
COLLISION_TIEBREAK = {
  # Brian's call: prefer C over C++/Objective-C for .h
  'h' => '4675A940-6227-11D9-BFB1-000D93589AF6'
}.freeze
# ----------------------------------------------------------------------------

PRIORITY_MANDATORY = 3
PRIORITY_SHIPPED   = 2
PRIORITY_AVAILABLE = 1
PRIORITY_UNKNOWN   = 0

def textmate_root
  ENV['TEXTMATE_ROOT'] || File.expand_path('..', __dir__)
end

def bundles_dir
  ENV['BUNDLES_DIR'] || File.expand_path('~/src/github.com/dayglojesus/bundles')
end

def bundle_support_dir
  ENV['BUNDLE_SUPPORT_DIR'] || File.expand_path('~/src/github.com/dayglojesus/bundle-support.tmbundle')
end

# Parse any .plist file to a Ruby object via `plutil -convert xml1 -o - <file>`.
# Wraps REXML parsing — kept behind one entry point so the strategy is
# swappable if/when the `plist` gem becomes available.
def parse_plist(path)
  out, err, status = Open3.capture3('plutil', '-convert', 'xml1', '-o', '-', path)
  unless status.success?
    raise "plutil failed for #{path}: #{err}"
  end
  doc = REXML::Document.new(out)
  root = doc.root.elements['dict'] || doc.root.elements['array']
  plist_value(root)
end

# Convert a single plist XML element into a Ruby value.
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

# Build the three uuid sets from catalogue files. Missing files are tolerated.
def load_priority_sets(root)
  mandatory = Set.new
  shipped   = Set.new
  available = Set.new

  mh = File.join(root, 'Frameworks/BundlesManager/src/MandatoryBundles.h')
  if File.exist?(mh)
    File.read(mh).scan(/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/).each do |u|
      mandatory << u.upcase
    end
  end

  db = File.join(root, 'Applications/TextMate/resources/DefaultBundles.plist')
  if File.exist?(db)
    data = parse_plist(db)
    (data['bundles'] || []).each { |b| shipped << b['uuid'].to_s.upcase if b['uuid'] }
  end

  ab = File.join(root, 'Applications/TextMate/resources/AvailableBundles.plist')
  if File.exist?(ab)
    data = parse_plist(ab)
    (data['bundles'] || []).each { |b| available << b['uuid'].to_s.upcase if b['uuid'] }
  end

  [mandatory, shipped, available]
end

def priority_for(uuid, mandatory, shipped, available)
  u = uuid.to_s.upcase
  return PRIORITY_MANDATORY if mandatory.include?(u)
  return PRIORITY_SHIPPED   if shipped.include?(u)
  return PRIORITY_AVAILABLE if available.include?(u)
  PRIORITY_UNKNOWN
end

# Parse a grammar file. Returns { 'scopeName' => .., 'fileTypes' => [..] } or nil.
def parse_grammar(path)
  if path.end_with?('.json')
    JSON.parse(File.read(path))
  else
    parse_plist(path)
  end
rescue StandardError => e
  warn "WARN: failed to parse grammar #{path}: #{e.message}"
  nil
end

# Walk a single bundle directory. Returns array of records:
#   { ext:, bundleUUID:, bundleName:, scopeName: }
def collect_bundle(bundle_dir)
  info_path = File.join(bundle_dir, 'info.plist')
  unless File.exist?(info_path)
    warn "WARN: skipping #{bundle_dir} — no info.plist"
    return []
  end

  info = parse_plist(info_path)
  uuid = info['uuid']
  name = info['name']
  unless uuid && name
    warn "WARN: skipping #{bundle_dir} — info.plist missing uuid or name"
    return []
  end

  syn_dir = File.join(bundle_dir, 'Syntaxes')
  return [] unless File.directory?(syn_dir)

  records = []
  Dir.children(syn_dir).sort.each do |entry|
    next unless entry =~ /\.(plist|tmLanguage|tmLanguage\.json)\z/

    g = parse_grammar(File.join(syn_dir, entry))
    next unless g.is_a?(Hash)

    fts = g['fileTypes'] || []
    scope = g['scopeName'] || ''
    fts.each do |ft|
      next if ft.nil? || ft.to_s.empty?

      records << {
        ext:        ft.to_s.downcase,
        bundleUUID: uuid.to_s.upcase,
        bundleName: name.to_s,
        scopeName:  scope.to_s
      }
    end
  end
  records
end

def each_bundle_dir(roots)
  roots.each do |root|
    next unless root && !root.empty? && File.directory?(root)

    if File.basename(root).end_with?('.tmbundle')
      yield root
    else
      Dir.children(root).sort.each do |child|
        path = File.join(root, child)
        yield path if child.end_with?('.tmbundle') && File.directory?(path)
      end
    end
  end
end

# Resolve collisions. Input: ext -> [records], plus priority sets.
# Output: ext -> winning record, OR raises with conflict info.
def resolve(by_ext, mandatory, shipped, available)
  winners = {}
  conflicts = []

  by_ext.each do |ext, recs|
    # Deduplicate by bundleUUID (a bundle may declare the same ext in two
    # grammars; treat that as a single claim).
    uniq = recs.uniq { |r| r[:bundleUUID] }
    if uniq.length == 1
      winners[ext] = uniq[0]
      next
    end

    by_priority = uniq.group_by do |r|
      priority_for(r[:bundleUUID], mandatory, shipped, available)
    end
    top = by_priority.keys.max
    top_recs = by_priority[top]

    if top_recs.length == 1
      winners[ext] = top_recs[0]
      next
    end

    tb = COLLISION_TIEBREAK[ext]
    if tb
      tb_up = tb.upcase
      candidate_uuids = top_recs.map { |r| r[:bundleUUID] }
      unless candidate_uuids.include?(tb_up)
        raise "COLLISION_TIEBREAK['#{ext}'] = #{tb} is not among candidates " \
              "#{candidate_uuids.inspect}. Fix the constant."
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
  mandatory, shipped, available = load_priority_sets(textmate_root)

  records = []
  each_bundle_dir([bundles_dir, bundle_support_dir]) do |bdir|
    records.concat(collect_bundle(bdir))
  end

  by_ext = records.group_by { |r| r[:ext] }
  winners, conflicts = resolve(by_ext, mandatory, shipped, available)

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

  out_path = File.join(textmate_root,
                       'Applications/TextMate/resources/BundleFileTypeIndex.plist')
  FileUtils.mkdir_p(File.dirname(out_path))
  File.write(out_path, render_plist(winners))
  puts "Wrote #{out_path} (#{winners.length} extensions, " \
       "#{records.map { |r| r[:bundleUUID] }.uniq.length} bundles)"
end

main if $PROGRAM_NAME == __FILE__
