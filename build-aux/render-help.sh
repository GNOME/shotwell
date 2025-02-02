#!/usr/bin/bash -e

mkdir doc-build
cd doc-build

cat <<EOF >meson.build
project('shotwell', [])
gnome=import('gnome')
i18n=import('i18n')
subdir('help')
EOF

ln -s ../help .
echo "C" >LINGUAS
cat help/LINGUAS >> LINGUAS
meson setup build
ninja -C build
cp -a help/C build/help
while read -r lang ; do
    cp -a help/C/figures "build/help/$lang"
    mkdir -p "html/$lang"
    yelp-build html -o "html/$lang" build/help/"$lang"/*.page
done < LINGUAS
mv html/C html/en
tar cf ../docs.tar html
