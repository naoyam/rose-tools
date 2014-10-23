#!/usr/bin/env bash
#
# Download, configure, build, and install the latest ROSE library.
#
#
# The JAVA_HOME environment variable must be set to the JDK directory (such as /usr/lib/jvm/java).
#
# After options are determined, each of the following commands can be selected.
# All steps are done by default. 
# - download
# - configure
# - make
# - make install

set -u
set -e

####################################
function die()
{
    local msg=$1
    echo "ERROR: $msg"
    exit 1
}
function display_help()
{
	cat <<EOF
Usage: rose-install.sh [-b <boost-path>] [-g <git-repo-name>] [-u]
  -b boost-path: Boost install top-level directory
  -g git-repo-name: Git repository name (legal names are: rose, edg4x-rose)
  -t: Use the tgz source package
  -u: Unattended mode
EOF
}
	
####################################
# Platform specific variables
TOP_DIR=$(pwd)
BOOST=/usr
UNATTENDED=0 # set to 0 to process each step interactively
###################################
# Use the rose git repository by default
GIT_REPO="rose"
while getopts ":b:g:uht" opt; do
    case $opt in
		g)
			GIT_REPO=$OPTARG
			;;
		t)
			GIT_REPO=""
			;;
		b)
			BOOST=$OPTARG
			;;
		u)
			UNATTENDED=1
			;;
		h)
			display_help
			exit 0
			;;
		\?)
			display_help
			die "Invalid option: -$OPTARG"
			;;
    esac
done

if [ -n "$GIT_REPO" ]; then
	TOP_DIR=$TOP_DIR/$GIT_REPO
else
	TOP_DIR=$TOP_DIR/tgz
fi
mkdir -p $TOP_DIR
TOP_SRC_DIR=$TOP_DIR/src
TOP_BUILD_DIR=$TOP_DIR/build
TOP_INSTALL_DIR=$TOP_DIR/install
mkdir -p $TOP_SRC_DIR
mkdir -p $TOP_BUILD_DIR
mkdir -p $TOP_INSTALL_DIR
mkdir -p $TOP_DIR/logs
####################################
function finish()
{
    echo "Finished successfully."
    exit 0
}

function is_git()
{
	if [ -n "$GIT_REPO" ]; then
		return 0
	else
		return 1
	fi
}

function get_tgz_name()
{
	# find the latest file naemd rose-0.9.*-without-EDG-*.tar.gz" in $TOP_DIR
	pushd $TOP_SRC_DIR > /dev/null
	local latest=$(ls -At rose-0.9.*-without-EDG-*.tar.gz | head -1)
	local name=$(basename $latest .tar.gz| sed 's/-without-EDG//')
	popd > /dev/null
	echo $name
}

function get_commit()
{
	if ! is_git; then
		die "No git repo set."
	fi
	pushd $(get_src_dir) > /dev/null
	local GIT_COMMIT=$(git rev-parse HEAD)
	popd > /dev/null
	echo ${GIT_COMMIT}
}

function get_src_id()
{
	if is_git; then
		get_commit
	else
		get_tgz_name
	fi
}

function get_src_dir()
{
	if is_git; then
		echo "$TOP_SRC_DIR"
	else
		echo "$TOP_SRC_DIR/$(get_tgz_name)"
	fi
}

function get_build_dir()
{
	echo "$TOP_BUILD_DIR/$(get_src_id)"
}

function get_install_prefix()
{
	echo "$TOP_INSTALL_DIR/$(get_src_id)"
}

function set_boost()
{
    if [ ! -d "$BOOST" ]; then
		die "Boost directory not found ($BOOST)" 
    fi
    if [ ! -d "$BOOST/include" ]; then
		die "Boost header files not found"
    fi
    echo Using Boost at $BOOST
    if [ -e "$BOOST/lib64/libboost_program_options.so" ]; then
        BOOSTLIB=$BOOST/lib64
    elif [ -e "$BOOST/lib/libboost_program_options.so" ]; then
        BOOSTLIB=$BOOST/lib
    else
        die "Boost library not found."
    fi  
}

function set_java_home()
{
    if [ -z "$JAVA_HOME" ]; then
		case $OSTYPE in
			linux*)
				for i in $(locate libjvm.so); do
					if echo $i | grep --silent -e gcc -e gcj; then continue; fi
					echo -n "Using $i? [Y/n] "
					read yn
					if [ "$yn" != "n" ]; then
						export JAVA_HOME=${i%/jre*}
						break
					fi
				done
				
				if [ -z "$JAVA_HOME" ]; then
					die "JDK not found"
				fi
				;;
			darwin*)
				JAVA_HOME=/System/Library/Frameworks/JavaVM.framework/Versions/CurrentJDK
				;;
		esac
    fi
    echo JAVA_HOME is set to $JAVA_HOME
}

function detect_java_libraries()
{
    local JVM_DIR=$(dirname $(find ${JAVA_HOME}/ -name "libjvm\.*" | head -1))
    case $OSTYPE in
		linux*)
			JAVA_LIBRARIES=${JAVA_HOME}/jre/lib:$JVM_DIR
			;;
		darwin*)
			JAVA_LIBRARIES=$JVM_DIR
			;;
    esac
}

function download_latest_tarball()
{
	if is_git; then
		die "Git is specified"
	fi
    local site='https://outreach.scidac.gov'
    echo "Detecting the latest ROSE source package..." 
    local path=$(wget --no-check-certificate --quiet -O- "$site/frs/?group_id=24" | egrep -o -m1 '/frs/download.php/[0-9]+/rose-0.9.5a-without-EDG-[0-9]+\.tar\.gz')
    local rose_file_name=$(basename $path)
    echo "Latest ROSE: $rose_file_name"
	pushd $TOP_SRC_DIR > /dev/null
    if [ -f $rose_file_name ]; then
		echo "The latest source is already downloaded"
    else
		echo "Downloading $site$path..."
		wget --no-check-certificate --progress=dot:giga $site$path
		echo "Download finished."
    fi
	local src_dir=$(get_src_dir)
    if [ -d $src_dir ]; then
		echo "The source is already unpacked."
    else
		echo "Unpacking the source..."
		tar zxf $(basename $path)
    fi
}

function download_latest_git()
{
	if ! is_git; then
		die "GIT repository not set"
	fi
	pushd $(get_src_dir) > /dev/null
	local git_url="https://github.com/rose-compiler/${GIT_REPO}.git"
	if [ ! -d .git ]; then
		echo "git clone $git_url..."
		git clone $git_url .
	else
		echo "git pull..."		
		git pull 
	fi
	./build	
	popd > /dev/null
}

function download()
{
	if is_git; then
		download_latest_git
	else
		download_latest_tarball
	fi
}

function exec_configure()
{
    if [ -z "$(get_src_dir)" ]; then die "ROSE src path not set"; fi
	local install_prefix=$(get_install_prefix)
    echo Configuring ROSE at $(get_src_dir)
	local build_dir=$(get_build_dir)
	if [ -d $build_dir ]; then
		echo "Removing previously used build dir: $build_dir"
		rm -rf $build_dir
	fi
	mkdir $build_dir
	cd $build_dir
    #local CONFIGURE_COMMAND="$(get_src_dir)/configure --prefix=$install_prefix --with-CXX_DEBUG=-g --with-CXX_WARNINGS='-Wall -Wno-deprecated' --with-boost=$BOOST --with-boost-libdir=$BOOSTLIB --enable-languages=c,c++,fortran,cuda,opencl"
	local CONFIGURE_COMMAND="$(get_src_dir)/configure --prefix=$install_prefix --with-CXX_DEBUG=-g --with-boost=$BOOST --with-boost-libdir=$BOOSTLIB"
	echo "Executing configure as: $CONFIGURE_COMMAND..."
    if [ $UNATTENDED -ne 1 ]; then
		echo -n "Type Enter to proceed: "
		read x
    fi
    eval ${CONFIGURE_COMMAND}
    if [ $? == 0 ]; then
		echo "Rerun again and select make for building ROSE"
    else
		die "configure failed"
    fi
}

function detect_num_cores()
{
    NUM_PROCESSORS=1 # default
    echo "Detecting number of cores..."
    case $OSTYPE in
		linux*)
			NUM_PROCESSORS=$(grep processor /proc/cpuinfo|wc -l)
			;;
		darwin*)
			NUM_PROCESSORS=$(system_profiler |grep 'Total Number Of Cores' | awk '{print $5}')
			;;
    esac
}

function exec_make()
{
    detect_num_cores
    echo "Building ROSE at $(get_build_dir) by make -j$(($NUM_PROCESSORS / 2))"
	pushd $(get_build_dir) > /dev/null
    make -j$(($NUM_PROCESSORS / 2))
    if [ $? == 0 ]; then
		echo "Rerun again and select make install to install ROSE"
    fi
	popd > /dev/null
}

function exec_install()
{
	local install_prefix=$(get_install_prefix)
    echo "Installing ROSE at $(get_build_dir) to $install_prefix"
    if [ -d $install_prefix ]; then
		echo "Removing previouslly installed ROSE of the latest version found."
		rm -rf $install_prefix
    fi
    pushd $(get_build_dir) > /dev/null
    make install
    echo "ROSE is installed at $install_prefix"
	popd > /dev/null
    rm -f $TOP_DIR/latest
    ln -s $install_prefix $TOP_DIR/latest
}

function clean_up_old_files()
{
	if ! is_git; then
		for d in $(ls -t $TOP_SRC_DIR/rose-0.9*-without-EDG-*.tar.gz | tail -n +2); do
			echo "Removing old downloaded src: $d"
			echo rm $d
		done
		for d in $(find $TOP_SRC_DIR -name "rose-0.*" -type d | ls -dt | tail -n +2); do
			echo "Removing old unpacked src: $d"
			rm -r $d
		done
	fi
    for d in $(ls -At $TOP_BUILD_DIR| tail -n +2); do
		echo "Removing old build dir: $d"
        rm -r $d
    done  
    for d in $(ls -At $TOP_INSTALL_DIR| tail -n +2); do
		echo "Removing old install dir: $d"
        rm -r $d
    done  
}

####################################

{
    set_boost
	set_java_home
    if [ "x" = "x$JAVA_HOME" ]; then
		die "JAVA_HOME not set"
    fi
    detect_java_libraries

	LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-""}
	DYLD_LIBRARY_PATH=${DYLD_LIBRARY_PATH:-""}

    case $OSTYPE in
		linux*)
			echo export LD_LIBRARY_PATH=${JAVA_LIBRARIES}:${BOOST}/lib:$LD_LIBRARY_PATH		
			export LD_LIBRARY_PATH=${JAVA_LIBRARIES}:${BOOST}/lib:$LD_LIBRARY_PATH
			;;
		darwin*)
			echo export DYLD_LIBRARY_PATH=${JAVA_LIBRARIES}:${BOOST}/lib:$DYLD_LIBRARY_PATH		
			export DYLD_LIBRARY_PATH=${JAVA_LIBRARIES}:${BOOST}/lib:$DYLD_LIBRARY_PATH
			;;
    esac

    typed_command=""
    if [ $UNATTENDED -ne 1 ]; then
		echo "Commands"
		echo "1: download"
		echo "2: configure"
		echo "3: make"
		echo "4: make install"
		echo "5: clean up"		
		echo "6: do all"
		echo -n "What to do? [1-6] (default: 6): "
		read typed_command
    fi
	if [ -z "$typed_command" ]; then
		command=6
	else
		command=$typed_command
	fi
    case $command in
		1)
			download
			;;
		2)
			exec_configure
			;;
		3)
			exec_make
			;;
		4)
			exec_install
			;;
		5)
			clean_up_old_files
			;;
		6)
			download
			exec_configure
			exec_make
			exec_install
            clean_up_old_files
			;;
		*)
			echo Invalid input \"$command\"
			;;
    esac

    finish
} 2>&1 | tee $TOP_DIR/logs/rose-install.$(date +%m-%d-%Y_%H-%M-%S).log
