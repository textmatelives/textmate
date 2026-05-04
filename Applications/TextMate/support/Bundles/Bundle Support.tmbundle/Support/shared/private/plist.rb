# encoding: utf-8

# Drop-in shim for the historical "plist" gem. Delegates to the
# OSX::PropertyList native extension shipped alongside this file
# (Support/shared/lib/osx/plist.bundle, universal arm64+x86_64).
#
# Replaces the prior submodule-vendored gem, which fetch_embedded_bundles.sh
# could not ship: GitHub's tarball API excludes submodule contents.

require "#{ENV['TM_SUPPORT_PATH']}/lib/osx/plist"

module Plist
  def self.parse_xml(filename_or_xml)
    src = filename_or_xml
    src = File.read(src) if src.is_a?(String) && !src.lstrip.start_with?('<') && File.file?(src)
    OSX::PropertyList.load(src)
  rescue StandardError
    nil
  end

  module Emit
    def to_plist(envelope = true)
      Plist::Emit.dump(self, envelope)
    end

    def save_plist(filename)
      File.open(filename, 'wb') { |f| f.write(to_plist) }
    end

    def self.dump(obj, envelope = true)
      out = OSX::PropertyList.dump(obj, OSX::PropertyList::XML1)
      return out if envelope
      out.sub(/\A.*?<plist[^>]*>\s*/m, '').sub(%r{\s*</plist>\s*\z}, '')
    end
  end
end

class Array; include Plist::Emit; end
class Hash;  include Plist::Emit; end
