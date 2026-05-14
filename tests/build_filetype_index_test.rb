#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'tmpdir'
require 'open3'
require 'digest'

SCRIPT_PATH = File.expand_path('../bin/build_filetype_index.rb', __dir__)

# Helper: build a fake bundle directory tree.
module FixtureHelper
  # Write a plist <dict> wrapper around arbitrary inner XML.
  def write_plist(path, inner_xml)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, <<~PLIST)
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
      <plist version="1.0">
      <dict>
      #{inner_xml}
      </dict>
      </plist>
    PLIST
  end

  # Build a .tmbundle directory at `path` with the given uuid + name + grammars.
  # grammars is an array of hashes: { file:, scope:, fileTypes: [..], format: :plist | :json }
  def make_bundle(path, uuid:, name:, grammars: [])
    FileUtils.mkdir_p(path)
    write_plist(File.join(path, 'info.plist'), <<~XML)
        <key>uuid</key><string>#{uuid}</string>
        <key>name</key><string>#{name}</string>
    XML
    return if grammars.empty?

    FileUtils.mkdir_p(File.join(path, 'Syntaxes'))
    grammars.each do |g|
      file = File.join(path, 'Syntaxes', g[:file])
      case g[:format]
      when :json
        File.write(file, JSON.dump('scopeName' => g[:scope], 'fileTypes' => g[:fileTypes]))
      else
        ftxml = g[:fileTypes].map { |e| "<string>#{e}</string>" }.join
        write_plist(file, <<~XML)
              <key>scopeName</key><string>#{g[:scope]}</string>
              <key>fileTypes</key><array>#{ftxml}</array>
        XML
      end
    end
  end

  # Build the three catalogue plist files. Each takes an array of uuid strings.
  def make_catalogues(textmate_root, mandatory:, shipped:, available:)
    fw_dir = File.join(textmate_root, 'Frameworks/BundlesManager/src')
    res_dir = File.join(textmate_root, 'Applications/TextMate/resources')
    FileUtils.mkdir_p(fw_dir)
    FileUtils.mkdir_p(res_dir)

    File.write(File.join(fw_dir, 'MandatoryBundles.h'), mandatory_h(mandatory))
    write_plist(File.join(res_dir, 'DefaultBundles.plist'),
                bundles_plist_entries(shipped))
    write_plist(File.join(res_dir, 'AvailableBundles.plist'),
                bundles_plist_entries(available))
  end

  def bundles_plist_entries(uuids)
    body = uuids.map { |u| "<dict><key>uuid</key><string>#{u}</string></dict>" }.join("\n")
    "<key>bundles</key><array>\n#{body}\n</array>"
  end

  def mandatory_h(uuids)
    entries = uuids.map do |u|
      %(\t{ "#{u}", "Name", "url", "sha", "cat" },\n)
    end.join
    <<~H
      static struct TMMandatoryBundle const kTMMandatoryBundles[] = {
      #{entries}};
    H
  end

  # Run the script with given env overrides.
  def run_script(bundles_dir:, support_dir: nil, textmate_root:, extra_env: {})
    env = {
      'BUNDLES_DIR' => bundles_dir,
      'BUNDLE_SUPPORT_DIR' => support_dir.to_s,
      'TEXTMATE_ROOT' => textmate_root
    }.merge(extra_env)
    Open3.capture3(env, 'ruby', SCRIPT_PATH)
  end

  def index_path(textmate_root)
    File.join(textmate_root, 'Applications/TextMate/resources/BundleFileTypeIndex.plist')
  end
end

class BuildFiletypeIndexTest < Minitest::Test
  include FixtureHelper

  def setup
    @tmpdir = Dir.mktmpdir('btidx-')
    @bundles = File.join(@tmpdir, 'bundles')
    @support = File.join(@tmpdir, 'support')
    @root = File.join(@tmpdir, 'textmate')
    FileUtils.mkdir_p([@bundles, @support, @root])
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- Test 1: happy path -------------------------------------------------
  def test_happy_path_two_bundles_no_collision
    uuid_py = '11111111-0000-0000-0000-000000000001'
    uuid_rb = '22222222-0000-0000-0000-000000000001'

    make_bundle(File.join(@bundles, 'python.tmbundle'),
                uuid: uuid_py, name: 'Python',
                grammars: [{ file: 'Python.plist', scope: 'source.python',
                             fileTypes: ['py'], format: :plist }])
    make_bundle(File.join(@bundles, 'ruby.tmbundle'),
                uuid: uuid_rb, name: 'Ruby',
                grammars: [{ file: 'Ruby.plist', scope: 'source.ruby',
                             fileTypes: ['rb'], format: :plist }])
    make_catalogues(@root, mandatory: [], shipped: [uuid_py, uuid_rb], available: [])

    stdout, stderr, status = run_script(bundles_dir: @bundles,
                                        support_dir: @support,
                                        textmate_root: @root)
    assert status.success?, "script failed: stdout=#{stdout}\nstderr=#{stderr}"

    out = File.read(index_path(@root))
    assert_match %r{<key>py</key>}, out
    assert_match %r{<key>rb</key>}, out
    assert_match %r{<string>#{uuid_py}</string>}, out
    assert_match %r{<string>#{uuid_rb}</string>}, out
  end

  # --- Test 2: empty Syntaxes/ ------------------------------------------
  def test_empty_syntaxes_dir_is_skipped
    uuid = '00000000-0000-0000-0000-000000000002'
    make_bundle(File.join(@bundles, 'empty.tmbundle'), uuid: uuid, name: 'Empty')
    FileUtils.mkdir_p(File.join(@bundles, 'empty.tmbundle', 'Syntaxes'))
    make_catalogues(@root, mandatory: [], shipped: [uuid], available: [])

    _stdout, _stderr, status = run_script(bundles_dir: @bundles,
                                          support_dir: @support,
                                          textmate_root: @root)
    assert status.success?, 'script should not crash on empty Syntaxes'
    out = File.read(index_path(@root))
    refute_match %r{<key>byExtension</key>\s*<dict>\s*<key>}, out,
                 'index should have no extensions'
  end

  # --- Test 3: cross-tier collision (mandatory beats available) ---------
  def test_cross_tier_collision_higher_priority_wins
    uuid_high = 'AAAAAAAA-0000-0000-0000-000000000003'
    uuid_low  = 'BBBBBBBB-0000-0000-0000-000000000003'

    make_bundle(File.join(@bundles, 'high.tmbundle'),
                uuid: uuid_high, name: 'High',
                grammars: [{ file: 'H.plist', scope: 'source.high',
                             fileTypes: ['x'], format: :plist }])
    make_bundle(File.join(@bundles, 'low.tmbundle'),
                uuid: uuid_low, name: 'Low',
                grammars: [{ file: 'L.plist', scope: 'source.low',
                             fileTypes: ['x'], format: :plist }])
    make_catalogues(@root, mandatory: [uuid_high], shipped: [],
                    available: [uuid_low])

    _stdout, _stderr, status = run_script(bundles_dir: @bundles,
                                          support_dir: @support,
                                          textmate_root: @root)
    assert status.success?
    out = File.read(index_path(@root))
    assert_match %r{<string>#{uuid_high.upcase}</string>}, out
    refute_match %r{<string>#{uuid_low.upcase}</string>}, out
  end

  # --- Test 4: same-tier collision, no tiebreak --> abort -----------------
  def test_same_tier_collision_without_tiebreak_aborts
    uuid_a = 'CCCCCCCC-0000-0000-0000-000000000004'
    uuid_b = 'DDDDDDDD-0000-0000-0000-000000000004'

    make_bundle(File.join(@bundles, 'a.tmbundle'),
                uuid: uuid_a, name: 'AAA',
                grammars: [{ file: 'A.plist', scope: 'source.a',
                             fileTypes: ['zzz'], format: :plist }])
    make_bundle(File.join(@bundles, 'b.tmbundle'),
                uuid: uuid_b, name: 'BBB',
                grammars: [{ file: 'B.plist', scope: 'source.b',
                             fileTypes: ['zzz'], format: :plist }])
    make_catalogues(@root, mandatory: [], shipped: [uuid_a, uuid_b],
                    available: [])

    _stdout, stderr, status = run_script(bundles_dir: @bundles,
                                         support_dir: @support,
                                         textmate_root: @root)
    refute status.success?, 'script must abort on uncurated collision'
    assert_match(/zzz/, stderr)
    assert_match(/AAA/, stderr)
    assert_match(/BBB/, stderr)
    refute File.exist?(index_path(@root)),
           'no plist should be written when collision unresolved'
  end

  # --- Test 5: same-tier collision, with tiebreak ------------------------
  def test_same_tier_collision_with_tiebreak_resolves
    # We piggyback on the .h tiebreak baked into the script
    # (C bundle UUID 4675A940-6227-11D9-BFB1-000D93589AF6).
    c_uuid   = '4675A940-6227-11D9-BFB1-000D93589AF6'
    cpp_uuid = 'EEEEEEEE-0000-0000-0000-000000000005'

    make_bundle(File.join(@bundles, 'c.tmbundle'),
                uuid: c_uuid, name: 'C',
                grammars: [{ file: 'C.plist', scope: 'source.c',
                             fileTypes: ['h'], format: :plist }])
    make_bundle(File.join(@bundles, 'cpp.tmbundle'),
                uuid: cpp_uuid, name: 'C++',
                grammars: [{ file: 'Cpp.plist', scope: 'source.c++',
                             fileTypes: ['h'], format: :plist }])
    make_catalogues(@root, mandatory: [],
                    shipped: [c_uuid, cpp_uuid], available: [])

    stdout, stderr, status = run_script(bundles_dir: @bundles,
                                        support_dir: @support,
                                        textmate_root: @root)
    assert status.success?, "expected tiebreak to resolve. stderr=#{stderr}\nstdout=#{stdout}"
    out = File.read(index_path(@root))
    assert_match %r{<key>h</key>}, out
    assert_match %r{<string>#{c_uuid}</string>}, out
    refute_match %r{<string>#{cpp_uuid.upcase}</string>}, out
  end

  # --- Test 6: tiebreak UUID not among candidates ------------------------
  def test_tiebreak_uuid_must_match_a_candidate
    # `.h` is in COLLISION_TIEBREAK pointing at the real C UUID, which is
    # NOT one of our fixture bundles below. Hence the script must abort.
    bogus_a = '00000000-0000-0000-0000-00000000AAAA'
    bogus_b = '00000000-0000-0000-0000-00000000BBBB'

    make_bundle(File.join(@bundles, 'a.tmbundle'),
                uuid: bogus_a, name: 'A',
                grammars: [{ file: 'A.plist', scope: 'source.a',
                             fileTypes: ['h'], format: :plist }])
    make_bundle(File.join(@bundles, 'b.tmbundle'),
                uuid: bogus_b, name: 'B',
                grammars: [{ file: 'B.plist', scope: 'source.b',
                             fileTypes: ['h'], format: :plist }])
    make_catalogues(@root, mandatory: [],
                    shipped: [bogus_a, bogus_b], available: [])

    _stdout, stderr, status = run_script(bundles_dir: @bundles,
                                         support_dir: @support,
                                         textmate_root: @root)
    refute status.success?
    assert_match(/COLLISION_TIEBREAK/, stderr)
    refute File.exist?(index_path(@root))
  end

  # --- Test 7: determinism ----------------------------------------------
  def test_two_runs_produce_byte_identical_output
    uuid = '00000000-0000-0000-0000-000000000007'
    make_bundle(File.join(@bundles, 'x.tmbundle'),
                uuid: uuid, name: 'X',
                grammars: [{ file: 'X.plist', scope: 'source.x',
                             fileTypes: %w[xa xb xc], format: :plist }])
    make_catalogues(@root, mandatory: [], shipped: [uuid], available: [])

    _o1, _e1, s1 = run_script(bundles_dir: @bundles, support_dir: @support, textmate_root: @root)
    assert s1.success?
    sha1 = Digest::SHA256.file(index_path(@root)).hexdigest

    _o2, _e2, s2 = run_script(bundles_dir: @bundles, support_dir: @support, textmate_root: @root)
    assert s2.success?
    sha2 = Digest::SHA256.file(index_path(@root)).hexdigest

    assert_equal sha1, sha2
  end

  # --- Test 8: JSON grammar variant -------------------------------------
  def test_json_grammar_variant_parses
    require 'json'
    uuid = '00000000-0000-0000-0000-000000000008'
    make_bundle(File.join(@bundles, 'j.tmbundle'),
                uuid: uuid, name: 'JSONLang',
                grammars: [{ file: 'J.tmLanguage.json', scope: 'source.j',
                             fileTypes: ['j8'], format: :json }])
    make_catalogues(@root, mandatory: [], shipped: [uuid], available: [])

    _o, e, s = run_script(bundles_dir: @bundles, support_dir: @support, textmate_root: @root)
    assert s.success?, "stderr=#{e}"
    out = File.read(index_path(@root))
    assert_match %r{<key>j8</key>}, out
  end

  # --- Test 9: missing info.plist ---------------------------------------
  def test_bundle_without_info_plist_is_skipped
    uuid_good = '00000000-0000-0000-0000-000000000099'
    # Good bundle so the run produces *something* and doesn't trigger an
    # empty-byExtension edge case.
    make_bundle(File.join(@bundles, 'good.tmbundle'),
                uuid: uuid_good, name: 'Good',
                grammars: [{ file: 'G.plist', scope: 'source.g',
                             fileTypes: ['gx'], format: :plist }])

    # Bad bundle: Syntaxes/ exists, info.plist missing.
    bad = File.join(@bundles, 'bad.tmbundle')
    FileUtils.mkdir_p(File.join(bad, 'Syntaxes'))
    write_plist(File.join(bad, 'Syntaxes', 'Bad.plist'), <<~XML)
            <key>scopeName</key><string>source.bad</string>
            <key>fileTypes</key><array><string>bx</string></array>
    XML
    make_catalogues(@root, mandatory: [], shipped: [uuid_good], available: [])

    _o, stderr, status = run_script(bundles_dir: @bundles, support_dir: @support, textmate_root: @root)
    assert status.success?
    assert_match(/info.plist/i, stderr)
    out = File.read(index_path(@root))
    assert_match %r{<key>gx</key>}, out
    refute_match %r{<key>bx</key>}, out
  end

  # --- Test 10: case normalization ---------------------------------------
  def test_filetype_uppercase_normalized_to_lowercase
    uuid = 'FFFFFFFF-0000-0000-0000-000000000010'
    make_bundle(File.join(@bundles, 'cap.tmbundle'),
                uuid: uuid, name: 'Cap',
                grammars: [{ file: 'Cap.plist', scope: 'source.cap',
                             fileTypes: ['PY'], format: :plist }])
    make_catalogues(@root, mandatory: [], shipped: [uuid], available: [])

    _o, _e, s = run_script(bundles_dir: @bundles, support_dir: @support, textmate_root: @root)
    assert s.success?
    out = File.read(index_path(@root))
    assert_match %r{<key>py</key>}, out
    refute_match %r{<key>PY</key>}, out
  end
end
