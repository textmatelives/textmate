# If this file is included from anything that uses ruby 1.8.7 then a line
# will be appended to:
#
#   ~/Library/Caches/com.macromates.TextMate/LegacyUsage.csv
#
# This file can then later be inspected to see which TextMate commands still
# need to be updated to use ruby 2.x.

if RUBY_VERSION == '1.8.7' && !defined?($textmate_migration_did_log)
  if logfile = ENV['TEXTMATE_MIGRATION_LOG']
    component = $PROGRAM_NAME.sub(/^#{Regexp.escape(ENV['HOME'])}(?=\/)/, '~')
    if line = caller.find { |line| line.start_with?(ENV['TM_SUPPORT_PATH'] + '/') }
      component = line.split(':', 2).first.sub(/^#{Regexp.escape(ENV['TM_SUPPORT_PATH'])}(?=\/)/, '$TM_SUPPORT_PATH')
    end

    open(logfile, 'a') do |io|
      cells = [
        Time.now.gmtime.strftime('%FT%TZ'),
        ENV['TM_BUNDLE_ITEM_UUID'] || 'null',
        ENV['TM_BUNDLE_ITEM_NAME'] || 'null',
        "ruby #{RUBY_VERSION}",
        component,
      ]
      io << "date,bundleItemUUID,bundleItemName,component,extra\n" if io.pos == 0
      io << cells.map { |cell| cell =~ /[",]/ ? '"' + cell.gsub(/"/, '""') + '"' : cell }.join(',') << "\n"
    end

    $textmate_migration_did_log = true
  end
end
