#!/bin/bash

granite_bzr_dir="${1}"

if [ ! -d "${granite_bzr_dir}" ]; then
    echo "==> need granite.bzr source directory"
    exit 1
fi

cp -rvf "${granite_bzr_dir}"/lib/{style-classes.vala,Drawing,Services} .
cp -vf "${granite_bzr_dir}"/lib/Widgets/Utils.vala ./Widgets/
