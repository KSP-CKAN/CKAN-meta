#!/bin/bash
set -e

# Default flags.
KSP_VERSION_DEFAULT="1.0.4"
KSP_NAME_DEFAULT="dummy"

# Locations of CKAN and validation.
LATEST_CKAN_URL="http://ckan-travis.s3.amazonaws.com/ckan.exe"
LATEST_CKAN_VALIDATE="https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/bin/ckan-validate.py"
LATEST_CKAN_SCHEMA="https://raw.githubusercontent.com/KSP-CKAN/CKAN/master/CKAN.schema"
LATEST_CKAN_META="https://github.com/KSP-CKAN/CKAN-meta/archive/master.tar.gz"

# Third party utilities.
JQ_PATH="jq"

# Return codes.
EXIT_OK=0

# Allow us to specify a commit id as the first argument
if [ -n "$1" ]
then
    echo "Using CLI argument of $1"
    ghprbActualCommit=$1
fi
    
# ------------------------------------------------
# Function for creating dummy KSP directories to
# test on. Takes version as an argument.
# ------------------------------------------------
create_dummy_ksp () {
    KSP_VERSION=$KSP_VERSION_DEFAULT
    KSP_NAME=$KSP_NAME_DEFAULT
    
    # Set the version to the requested KSP version if supplied.
    if [ $# -eq 2 ]
    then
        KSP_VERSION=$1
        KSP_NAME=$2
    fi
    
    # TODO: Manual hack, a better way to handle this kind of identifiers may be needed.
    case $KSP_VERSION in
    "0.90")
        echo "Overidding '0.90' with '0.90.0'"
        KSP_VERSION="0.90.0"
        ;;
    "1.0")
        echo "Overidding '1.0' with '$KSP_VERSION_DEFAULT'"
        KSP_VERSION=$KSP_VERSION_DEFAULT
        ;;
    "any")
        echo "Overridding any with '$KSP_VERSION_DEFAULT'"
        KSP_VERSION=$KSP_VERSION_DEFAULT
        ;;
    "null")
        echo "Overridding 'null' with '$KSP_VERSION_DEFAULT'"
        KSP_VERSION=$KSP_VERSION_DEFAULT
        ;;
    "")
        echo "Overridding empty version with '$KSP_VERSION_DEFAULT'"
        KSP_VERSION=$KSP_VERSION_DEFAULT
        ;;
    *)
        echo "No override, Running with '$KSP_VERSION'"
        ;;
    esac
    
    echo "Creating a dummy KSP '$KSP_VERSION' install"
    
    # Remove any existing KSP dummy install.
    if [ -d "dummy_ksp/" ]
    then
        rm -rf dummy_ksp
    fi
    
    # Create a new dummy KSP.
    mkdir dummy_ksp
    mkdir dummy_ksp/CKAN
    mkdir dummy_ksp/GameData
    mkdir dummy_ksp/Ships/
    mkdir dummy_ksp/Ships/VAB
    mkdir dummy_ksp/Ships/SPH
    mkdir dummy_ksp/Ships/@thumbs
    mkdir dummy_ksp/Ships/@thumbs/VAB
    mkdir dummy_ksp/Ships/@thumbs/SPH
    
    echo "Version $KSP_VERSION" > dummy_ksp/readme.txt
    
    # Copy in resources.
    cp ckan.exe dummy_ksp/ckan.exe
    
    # Reset the Mono registry.
    if [ "$USER" = "jenkins" ]
    then
        REGISTRY_FILE=$HOME/.mono/registry/CurrentUser/software/ckan/values.xml
        if [ -r $REGISTRY_FILE ]
        then
            rm -f $REGISTRY_FILE
        fi
    fi
    
    # Register the new dummy install.
    mono ckan.exe ksp add $KSP_NAME "`pwd`/dummy_ksp"
    
    # Set the instance to default.
    mono ckan.exe ksp default $KSP_NAME
    
    # Point to the local metadata instead of GitHub.
    mono ckan.exe repo add local "file://`pwd`/master.tar.gz"
    mono ckan.exe repo remove default
    
    # Link to the downloads cache.
    ln -s downloads_cache dummy_ksp/CKAN/downloads
}

# ------------------------------------------------
# Function for injecting metadata into a tar.gz
# archive. Assummes metadata.tar.gz to be present.
# ------------------------------------------------
inject_metadata () {
    # TODO: Arrays + Bash Functions aren't fun. This needs
    # Improvement but appears to work. The variables are
    # available to the called functions.

    # Check input, requires at least 1 argument.
    if [ $# -ne 1 ]
    then
        echo "Nothing to inject."
        cp metadata.tar.gz master.tar.gz
        return 0
    fi
   
    # Extract the metadata into a new folder.
    rm -rf CKAN-meta-master
    tar -xzf metadata.tar.gz
    
    # Copy in the files to inject.
    # TODO: Unsure why this suddenly needs [*] declaration
    # but it does work
    for f in ${OTHER_FILES[*]}
    do
        echo "Injecting $f"
        cp $f CKAN-meta-master
    done
    
    # Recompress the archive.
    rm -f master.tar.gz
    tar -czf master.tar.gz CKAN-meta-master
}

# ------------------------------------------------
# Main entry point.
# ------------------------------------------------

# Find the changes to test.
echo "Finding changes to test..."

if [ -n "$ghprbActualCommit" ]
then
    echo "Commit hash: $ghprbActualCommit"
    export COMMIT_CHANGES="`git diff --diff-filter=AM --name-only --stat origin/master`"
else
    echo "No commit provided, skipping further tests."
    exit $EXIT_OK
fi

# Make sure we start from a clean slate.
if [ -d "downloads_cache/" ]
then
    rm -rf downloads_cache
fi

if [ -e "master.tar.gz" ]
then
    rm -f master.tar.gz
fi

if [ -e "metadata.tar.gz" ]
then
    rm -f metadata.tar.gz
fi

# CKAN Validation files
wget --quiet $LATEST_CKAN_VALIDATE -O ckan-validate.py
wget --quiet $LATEST_CKAN_SCHEMA -O CKAN.schema
chmod a+x ckan-validate.py

# fetch latest ckan.exe
echo "Fetching latest ckan.exe"
#wget --quiet $LATEST_CKAN_URL -O ckan.exe

# Fetch the latest metadata.
echo "Fetching latest metadata"
wget --quiet $LATEST_CKAN_META -O metadata.tar.gz

# Create folders.
# TODO: Point to cache folder here instead if possible.
if [ ! -d "downloads_cache/" ]
then
    mkdir downloads_cache
fi

for ckan in $COMMIT_CHANGES
do
    # set -e doesn't apply inside an if block CKAN#1273
    if [ "$ckan" = "build.sh" ]; then
      echo "Lets try not to validate our build script with CKAN"
      continue
    fi
    
    ./ckan-validate.py $ckan
    echo ----------------------------------------------
    cat $ckan | python -m json.tool
    echo ----------------------------------------------

    # Extract identifier and KSP version.
    CURRENT_IDENTIFIER=$($JQ_PATH '.identifier' $ckan)
    CURRENT_KSP_VERSION=$($JQ_PATH 'if .ksp_version then .ksp_version else .ksp_version_min end' $ckan)
    
    # Strip "'s.
    CURRENT_IDENTIFIER=${CURRENT_IDENTIFIER//'"'}
    CURRENT_KSP_VERSION=${CURRENT_KSP_VERSION//'"'}
    
    echo "Extracted $CURRENT_IDENTIFIER as identifier."
    echo "Extracted $CURRENT_KSP_VERSION as KSP version."
    
    # Get a list of all the OTHER files.
    OTHER_FILES=()
   
    for o in $COMMIT_CHANGES
    do
        if [ "$ckan" != "$o" ] && [ "$ckan" != "build.sh" ]
        then
            OTHER_FILES+=($o)
        fi
    done
    echo "Other files: ${OTHER_FILES[*]}"

    # Inject into metadata.
    inject_metadata $OTHER_FILES
    
    # Create a dummy KSP install.
    create_dummy_ksp $CURRENT_KSP_VERSION $ghprbActualCommit

    echo "Running ckan update"
    mono ckan.exe update

    echo Running ckan install -c $ckan
    mono --debug ckan.exe install -c $ckan --headless

    # Show all installed mods.
    echo "Installed mods:"
    mono --debug ckan.exe list --porcelain
    
    # Check the installed files for this .ckan file.
    mono ckan.exe show $CURRENT_IDENTIFIER
    
    # Cleanup.
    mono ckan.exe ksp forget $KSP_NAME
done
