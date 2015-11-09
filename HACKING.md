## Install debug pacakges
```
sudo apt-get install gdb deepin-mutter-dbg deepin-wm-dbg libx11-6-dbg \
     libglib2.0-0-dbg libgtk-3-0-dbg libclutter-1.0-dbg libcogl20-dbg \
     xserver-xorg-core-dbg libgl1-mesa-glx-dbg libegl1-mesa-dbg \
     libpixman-1-0-dbg libcogl20-dbg libgl1-mesa-dri-dbg
```

## Use debug environment variables

**MUTTER_DEBUG**
```
env MUTTER_DEBUG=t deepin-wm
env MUTTER_DEBUG="WINDOW_STATE SYNC" deepin-wm
```

**LIBGL_DEUBG**
```
env LIBGL_DEBUG=verbose deepin-wm
```

## Debug in source directory
```
./autogen --prefix=/usr
make
gdb src/.libs/gala
```

## Debug with mutter as backend
```
sed -i 's/libdeepin-mutter/libmutter/g' configure.ac
make
src/.libs/gala --replace
```

## Collect gdb backtrace messages
```
gdb -batch -ex "bt" deepin-wm /var/debug/deepin-wm.core
gdb -batch -ex "bt full" deepin-wm /var/debug/deepin-wm.core
```

## Merge upstream code

1. Install `git-bzr`
```
sudo apt-get install git-bzr
```
2. Pull upstream gala code
```
git checkout upstream-bzr
git pull bzr::lp:gala
```
3. Cherry-pick upstream code to master branch (**NOTE**: we should use
   `git cherry-pick` instead of `git merge` here, or the broken bzr
   authro email information will cause pushing to Github failed)
```
git checkout master
git cherry-pick A..B
```
