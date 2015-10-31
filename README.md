# Deepin Window Manager

**Description**: Default window manager for Deepin.

This project started as a fork of
[Elementary Gala](https://launchpad.net/gala) which is a window &
compositing manager based on libmutter. But we rewrote most of the
code to make it works well with Deepin Desktop Environment, such as
redesign the UI for window switching, enhance user experience for the
workspace preview mode, support multiple backgrounds, and many of
other changes.

## Dependencies

### Build dependencies

- valac (>= 0.22.0)
- gsettings-desktop-schemas (>= 3.15.92)

### Runtime dependencies

- clutter-1.0 (>= 1.9.16)
- clutter-gtk-1.0
- [deepin-desktop-schemas](https://github.com/linuxdeepin/deepin-desktop-schemas)
- gee-0.8
- glib-2.0 (>= 2.32)
- gnome-desktop-3.0
- gtk+-3.0 (>= 3.4.0)
- libbamf3
- libcanberra
- libcanberra-gtk3
- [libdeepin-mutter](https://github.com/linuxdeepin/deepin-mutter)

## Installation

### Debian 8.0 (jessie)

Install prerequisites
```
$ sudo apt-get install \
               dh-autoreconf \
               gnome-common \
               gsettings-desktop-schemas-dev \
               libbamf3-dev \
               libcanberra-dev \
               libcanberra-gtk3-dev \
               libclutter-1.0-dev \
               libclutter-gtk-1.0-dev \
               libgee-0.8-dev \
               libglib2.0-dev \
               libgnome-desktop-3-dev \
               libgtk-3-dev \
               libdeepin-mutter-dev \
               valac \
               deepin-desktop-schemas
```

Build
```
$ ./autogen.sh --prefix=/usr && make
```

If you have isolated testing build environment (say a docker container), you can install it directly
```
$ sudo make install
```

Or, generate package files and install Deepin Window Manager with it
```
$ debuild -uc -us ...
$ sudo dpkg -i ../deepin-mutter-*deb
```

## Usage

Run Deepin Window Manager to replace current window manager with the command below
```
$ deepin-wm --replace &
```

## Getting help

Any usage issues can ask for help via

* [Gitter](https://gitter.im/orgs/linuxdeepin/rooms)
* [IRC channel](https://webchat.freenode.net/?channels=deepin)
* [Forum](https://bbs.deepin.org)
* [WiKi](http://wiki.deepin.org/)

## Getting involved

We encourage you to report issues and contribute changes

* [Contribution guide for users](http://wiki.deepin.org/index.php?title=Contribution_Guidelines_for_Users)
* [Contribution guide for developers](http://wiki.deepin.org/index.php?title=Contribution_Guidelines_for_Developers).

## License

Deepin Window Manager is licensed under [GPLv3](LICENSE).
