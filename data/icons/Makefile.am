pkgicon32dir = @datadir@/icons/hicolor/32x32/apps
dist_pkgicon32_DATA = 32x32/multitasking-view.png

pkgicon48dir = @datadir@/icons/hicolor/48x48/apps
dist_pkgicon48_DATA = 48x48/multitasking-view.png

pkgicon64dir = @datadir@/icons/hicolor/64x64/apps
dist_pkgicon64_DATA = 64x64/multitasking-view.png

pkgiconscalabledir = @datadir@/icons/hicolor/scalable/apps
dist_pkgiconscalable_DATA = scalable/multitasking-view.svg

# rename data file with prefix 'deepin'
install-data-hook:
	mv $(DESTDIR)$(pkgicon32dir)/multitasking-view.png $(DESTDIR)$(pkgicon32dir)/deepin-multitasking-view.png
	mv $(DESTDIR)$(pkgicon48dir)/multitasking-view.png $(DESTDIR)$(pkgicon48dir)/deepin-multitasking-view.png
	mv $(DESTDIR)$(pkgicon64dir)/multitasking-view.png $(DESTDIR)$(pkgicon64dir)/deepin-multitasking-view.png
	mv $(DESTDIR)$(pkgiconscalabledir)/multitasking-view.svg $(DESTDIR)$(pkgiconscalabledir)/deepin-multitasking-view.svg
