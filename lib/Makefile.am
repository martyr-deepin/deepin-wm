include $(top_srcdir)/Makefile.common

VAPIDIR = $(top_srcdir)/vapi

BUILT_SOURCES = \
	libdeepin_wm_la_vala.stamp \
	$(NULL)

libdeepin_wmincludedir = $(includedir)/gala
nodist_libdeepin_wminclude_HEADERS = gala.h

vapidir = $(datadir)/vala/vapi
nodist_vapi_DATA = \
	gala.vapi \
	gala.deps \
	$(NULL)

pkgconfigdir = $(libdir)/pkgconfig
nodist_pkgconfig_DATA = gala.pc


lib_LTLIBRARIES = libdeepin-wm.la

libdeepin_wm_la_CFLAGS = \
	$(GALA_CORE_CFLAGS) \
	-include config.h \
	-w \
	$(NULL)

libdeepin_wm_la_LDFLAGS = \
	$(AM_LDLAGS) \
	$(GALA_CORE_LDFLAGS) \
	-no-undefined \
	-version-info "$(LT_CURRENT)":"$(LT_REVISION)":"$(LT_AGE)" \
	-export-dynamic \
	-export-symbols-regex '^gala_.*' \
	$(NULL)

libdeepin_wm_la_VALAFLAGS = \
	$(GALA_CORE_VALAFLAGS) \
	--vapidir $(VAPIDIR) \
	$(VAPIDIR)/config.vapi \
	$(NULL)

libdeepin_wm_la_LIBADD = \
	$(GALA_CORE_LIBS) \
	$(NULL)

libdeepin_wm_la_VALASOURCES = \
	ActivatableComponent.vala \
	Plugin.vala \
	Utils.vala \
	WindowIcon.vala \
	WindowManager.vala \
	Granite/style-classes.vala \
	Granite/Drawing/Color.vala \
	Granite/Drawing/BufferSurface.vala \
	Granite/Drawing/Utilities.vala \
	Granite/Widgets/Utils.vala \
	Granite/Services/Settings.vala \
	Plank/DockPreferences.vala \
	Plank/FixCode.vala \
	Plank/Drawing/DrawingService.vala \
	Plank/Drawing/Color.vala \
	Plank/Drawing/DockTheme.vala \
	Plank/Drawing/Theme.vala \
	Plank/Drawing/DockSurface.vala \
	Plank/Services/Logger.vala \
	Plank/Services/Paths.vala \
	Plank/Services/Preferences.vala \
	$(NULL)

nodist_libdeepin_wm_la_SOURCES = \
	$(BUILT_SOURCES) \
	$(libdeepin_wm_la_VALASOURCES:.vala=.c) \
	$(NULL)

gala.h gala.vapi: libdeepin_wm_la_vala.stamp

libdeepin_wm_la_vala.stamp: $(libdeepin_wm_la_VALASOURCES) Makefile
	$(AM_V_VALA)$(VALAC) \
		$(libdeepin_wm_la_VALAFLAGS) \
		--basedir $(srcdir) \
		--directory $(builddir) \
		-C \
		-H gala.h \
		--vapi gala.vapi \
		--library gala \
		$(filter %.vala %.c,$^)
	$(AM_V_at)touch $@

CLEANFILES = \
	$(nodist_libdeepin_wm_la_SOURCES) \
	gala.vapi \
	gala.h \
	$(NULL)

EXTRA_DIST = \
	$(libdeepin_wm_la_VALASOURCES) \
	gala.deps \
	$(NULL)

install-data-hook:
	mv $(DESTDIR)$(includedir)/gala/gala.h $(DESTDIR)$(includedir)/gala/deepin-wm.h
	mv $(DESTDIR)$(includedir)/gala $(DESTDIR)$(includedir)/deepin-wm
	mv $(DESTDIR)$(vapidir)/gala.deps $(DESTDIR)$(vapidir)/deepin-wm.deps
	mv $(DESTDIR)$(vapidir)/gala.vapi $(DESTDIR)$(vapidir)/deepin-wm.vapi
	mv $(DESTDIR)$(pkgconfigdir)/gala.pc $(DESTDIR)$(pkgconfigdir)/deepin-wm.pc
