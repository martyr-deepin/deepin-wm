include $(top_srcdir)/Makefile.common

SUBDIRS = \
	data \
	lib \
	plugins \
	src \
	docs \
	po \
	vapi \
	$(NULL)

EXTRA_DIST = \
	.version \
	build-aux/bzr-version-gen \
	$(NULL)

BUILT_SOURCES = \
	$(top_srcdir)/.version \
	$(NULL)

$(top_srcdir)/.version:
	echo $(VERSION) > $@-t && mv $@-t $@

dist-hook:
	echo $(VERSION) > $(distdir)/.tarball-version

distclean-local:
	if test "x$(srcdir)" = "x."; then :; else \
		rm -f ChangeLog; \
	fi
