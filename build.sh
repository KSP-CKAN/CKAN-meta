#!/bin/bash

set -x
set -e

# Locations of CKAN and NetKAN.
LATEST_CKAN_URL="http://ckan-travis.s3.amazonaws.com/ckan.exe"

echo Commit hash: ${ghprbActualCommit}
echo Changes in this commit:
export COMMIT_CHANGES="`git diff --diff-filter=AM --name-only --stat origin/master`"
echo ${COMMIT_CHANGES}

wget --quiet https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/bin/ckan-validate.py -O ckan-validate.py
wget --quiet https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/CKAN.schema -O CKAN.schema
chmod a+x ckan-validate.py

# fetch latest ckan.exe
echo "Fetching latest ckan.exe"
wget --quiet $LATEST_CKAN_URL -O ckan.exe

# create a dummy KSP install
mkdir dummy_ksp
echo Version 1.0.4 > dummy_ksp/readme.txt
mkdir dummy_ksp/GameData
mkdir dummy_ksp/Ships/
mkdir dummy_ksp/Ships/VAB
mkdir dummy_ksp/Ships/SPH
mkdir dummy_ksp/Ships/@thumbs
mkdir dummy_ksp/Ships/@thumbs/VAB
mkdir dummy_ksp/Ships/@thumbs/SPH

mono --debug ckan.exe ksp add ${ghprbActualCommit} "`pwd`/dummy_ksp"
mono --debug ckan.exe ksp default ${ghprbActualCommit}
mono --debug ckan.exe update

for f in ${COMMIT_CHANGES}
do
  if [ "$f" != "build.sh" ]; then
        ./ckan-validate.py $f
        echo ----------------------------------------------
        echo 
        cat $f | python -m json.tool
        echo ----------------------------------------------
        echo 
        echo Running ckan install -c $f
        mono --debug ckan.exe install -c $f --headless
  fi
done

# Show all installed mods.

echo "Installed mods:"
mono --debug ckan.exe list --porcelain

perl -e'@installed = `mono --debug ckan.exe list --porcelain`; foreach (@installed) { /^\S\s(?<mod>\S+)/ and system("mono --debug ckan.exe show $+{mod}"); print "\n\n"; } exit 0;'
    
# Cleanup.
mono ckan.exe ksp forget ${ghprbActualCommit}
