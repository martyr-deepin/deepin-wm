SUBDIRS = \
	icons \
	$(NULL)

stylesdir = $(pkgdatadir)
styles_DATA = deepin-wm.css texture.png close.png \
	close_hover.png \
	close_normal.png \
	close_press.png \
	sticked_hover.png \
	sticked_normal.png \
	sticked_press.png \
	unsticked_hover.png \
	unsticked_normal.png \
	unsticked_press.png \
	deepin-toggle-desktop.svg \
	close_marker_1.png \
	close_marker_2.png \
	close_marker_3.png \
	close_marker_4.png \
	close_marker_5.png \
	close_marker_6.png \
	close_marker_7.png \
	close_marker_press.png \
	topleft.png \
	topright.png \
	bottomleft.png \
	bottomright.png \
	path.svg

applicationsdir = $(datadir)/applications
applications_DATA = gala.desktop gala-wayland.desktop gala-multitaskingview.desktop

@INTLTOOL_DESKTOP_RULE@

gsettings_SCHEMAS = org.pantheon.desktop.gala.gschema.xml

@INTLTOOL_XML_NOMERGE_RULE@

@GSETTINGS_RULES@

gschemas.compiled: Makefile $(gsettings_SCHEMAS:.xml=.valid)
	$(AM_V_GEN) $(GLIB_COMPILE_SCHEMAS) --targetdir=$(builddir) $(builddir)

all-local: gschemas.compiled

EXTRA_DIST = \
	deepin-test.desktop \
	deepin-wm.css \
	gala.desktop \
	gala-wayland.desktop \
	gala-multitaskingview.desktop.in \
	texture.png \
	close.png \
	deepin-toggle-desktop.svg \
	close_marker_1.png \
	close_marker_2.png \
	close_marker_3.png \
	close_marker_4.png \
	close_marker_5.png \
	close_marker_6.png \
	close_marker_7.png \
	close_marker_press.png \
	close_hover.png \
	close_normal.png \
	close_press.png \
	sticked_hover.png \
	sticked_normal.png \
	sticked_press.png \
	unsticked_hover.png \
	unsticked_normal.png \
	unsticked_press.png \
	topleft.png \
	topright.png \
	bottomleft.png \
	bottomright.png \
	path.svg \
	org.pantheon.desktop.gala.gschema.xml.in.in \
	$(NULL)

CLEANFILES = \
	gala-multitaskingview.desktop \
	gschemas.compiled \
	org.pantheon.desktop.gala.gschema.xml \
	org.pantheon.desktop.gala.gschema.xml.in \
	$(NULL)

# rename data file with prefix 'deepin'
install-data-hook:
	mv $(DESTDIR)$(applicationsdir)/gala.desktop $(DESTDIR)$(applicationsdir)/deepin-wm.desktop
	mv $(DESTDIR)$(applicationsdir)/gala-wayland.desktop $(DESTDIR)$(applicationsdir)/deepin-wm-wayland.desktop
	mv $(DESTDIR)$(applicationsdir)/gala-multitaskingview.desktop $(DESTDIR)$(applicationsdir)/deepin-wm-multitaskingview.desktop
	mv $(DESTDIR)$(gsettingsschemadir)/org.pantheon.desktop.gala.gschema.xml $(DESTDIR)$(gsettingsschemadir)/com.deepin.wrap.pantheon.desktop.gala.gschema.xml
