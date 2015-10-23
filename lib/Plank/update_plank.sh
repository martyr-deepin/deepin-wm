#!/bin/bash

plank_bzr_dir="${1}"

if [ ! -d "${plank_bzr_dir}" ]; then
    echo "==> need plank.bzr source directory, just clone the code through 'bzr branch lp:plank'"
    exit 1
fi


cp -rvf "${plank_bzr_dir}"/lib/DockPreferences.vala .

mkdir -p Drawing
cp -rvf "${plank_bzr_dir}"/lib/Drawing/*.vala ./Drawing/

mkdir -p Services
cp -vf "${plank_bzr_dir}"/lib/Services/*.vala ./Services/

find . -iname '*.vala' | xargs sed -i -e 's/namespace Plank/namespace Gala.Plank/' \
                               -e 's/using Plank\./using Gala.Plank./'
