RUBY_HDR     := $(shell ruby -e "puts RbConfig::CONFIG['rubyhdrdir']")
RUBY_ARCH_HDR := $(shell ruby -e "puts RbConfig::CONFIG['rubyarchhdrdir']")

CC       := clang
CFLAGS   := -I$(RUBY_HDR) -I$(RUBY_ARCH_HDR) -fPIC -Wall -O2 -Wno-compound-token-split-by-macro -Wno-deprecated-declarations
LDFLAGS  := -bundle -undefined dynamic_lookup -framework CoreFoundation -framework Security

OUTDIR   := ..

all: $(OUTDIR)/plist.bundle $(OUTDIR)/keychain.bundle

$(OUTDIR)/plist.bundle: plist.c
	$(CC) $(CFLAGS) -arch arm64 -arch x86_64 $< -o $@ $(LDFLAGS)

$(OUTDIR)/keychain.bundle: keychain.c
	$(CC) $(CFLAGS) -arch arm64 -arch x86_64 $< -o $@ $(LDFLAGS)

clean:
	rm -f $(OUTDIR)/plist.bundle $(OUTDIR)/keychain.bundle

.PHONY: all clean
