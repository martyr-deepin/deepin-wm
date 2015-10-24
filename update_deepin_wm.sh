#!/bin/bash

# migrate code from mutter to deepin-mutter
appname="$(basename $0)"

grep_ignore_files="${appname}\|README\|NEWS\|Makefile.am\|configure.ac\|\.git\|\.bzr\|\./po\|\./debian\|\./lib/Granite"

echo "==> show gsettings path with prefix 'org.gnome' or 'org.pantheon'"
find . -type f | grep -v "${grep_ignore_files}" | xargs grep -P '(org.gnome|org.pantheon).[^A-Z]'

# echo "==> show gsettings path with prefix 'org.pantheon'"
# find . -type f | grep -v "${grep_ignore_files}" | xargs grep -P 'org.pantheon.[^A-Z]'

echo "==> replace gsettings path"
for f in $(find . -type f | grep -v "${grep_ignore_files}" | xargs grep -l -P '(org.gnome|org.pantheon).[^A-Z]'); do
  echo "  -> ${f}"
  sed -e 's=org\.gnome\.\([^A-Z]\)=com.deepin.wrap.gnome.\1=g' \
      -e 's=org\.pantheon\.\([^A-Z]\)=com.deepin.wrap.pantheon.\1=g' \
      -e 's=/org/gnome/\([^A-Z]\)=/com/deepin/wrap/gnome/\1=g' \
      -e 's=/org/pantheon/\([^A-Z]\)=/com/deepin/wrap/pantheon/\1=g' \
      -e 's="GalaActionType="WrapGalaActionType=g' \
      -e 's="GalaWindowOverviewType="WrapGalaWindowOverviewType=g' \
      -i "${f}"
done
