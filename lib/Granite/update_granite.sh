#!/bin/bash

granite_bzr_dir="${1}"

if [ ! -d "${granite_bzr_dir}" ]; then
    echo "==> need granite.bzr source directory, just clone the code through 'bzr branch lp:granite'"
    exit 1
fi

cp -rvf "${granite_bzr_dir}"/lib/{style-classes.vala,Drawing,Services} .

mkdir -p Widgets
cp -vf "${granite_bzr_dir}"/lib/Widgets/Utils.vala ./Widgets/

find . -iname '*.vala' | xargs sed -i -e 's/namespace Granite/namespace Gala.Granite/' \
                               -e 's/using Granite\./using Gala.Granite./' \
                               -e 's/enum Granite\./enum Gala.Granite./'
