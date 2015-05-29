#!/bin/bash

set -x
set -e

echo Commit hash: ${ghprbActualCommit}
echo Changes in this commit:
export COMMIT_CHANGES="`git diff --diff-filter=AM --name-only --stat origin/master`"
echo ${COMMIT_CHANGES}

wget --quiet https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/bin/ckan-validate.py -O ckan-validate.py
wget --quiet https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/CKAN.schema -O CKAN.schema
chmod a+x ckan-validate.py
./ckan-validate.py ${COMMIT_CHANGES}

# fetch latest ckan.exe
wget --quiet http://ci.ksp-ckan.org:8080/job/CKAN/lastSuccessfulBuild/artifact/ckan.exe -O ckan.exe

# create a dummy KSP install
mkdir dummy_ksp
echo Version 1.0.2 > dummy_ksp/readme.txt
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
	echo ----------------------------------------------
	echo 
	cat $f | python -m json.tool
	echo ----------------------------------------------
	echo 
	echo Running ckan install -c $f
	mono --debug ckan.exe install -c $f --headless
done

# Show all installed mods.

echo "Installed mods:"
mono --debug ckan.exe list --porcelain

perl -e'@installed = `mono --debug ckan.exe list --porcelain`; foreach (@installed) { /^\S\s(?<mod>\S+)/ and system("mono --debug ckan.exe show $+{mod}"); print "\n\n"; } exit 0;'
