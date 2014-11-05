pkgicon32dir = @datadir@/icons/hicolor/32x32/apps
dist_pkgicon32_DATA = 32x32/multitasking-view.svg

pkgicon48dir = @datadir@/icons/hicolor/48x48/apps
dist_pkgicon48_DATA = 48x48/multitasking-view.svg

pkgicon64dir = @datadir@/icons/hicolor/64x64/apps
dist_pkgicon64_DATA = 64x64/multitasking-view.svg

# rename data file with prefix 'deepin'
install-data-hook:
	mv $(DESTDIR)$(pkgicon32dir)/multitasking-view.svg $(DESTDIR)$(pkgicon32dir)/deepin-multitasking-view.svg
	mv $(DESTDIR)$(pkgicon48dir)/multitasking-view.svg $(DESTDIR)$(pkgicon48dir)/deepin-multitasking-view.svg
	mv $(DESTDIR)$(pkgicon64dir)/multitasking-view.svg $(DESTDIR)$(pkgicon64dir)/deepin-multitasking-view.svg
