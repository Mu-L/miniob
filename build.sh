#!/bin/bash

# readlink -f cannot work on mac
TOPDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

BUILD_SH=$TOPDIR/build.sh
echo "THIRD_PARTY_INSTALL_PREFIX is ${THIRD_PARTY_INSTALL_PREFIX:=$TOPDIR/deps/3rd/usr/local}"

CMAKE_COMMAND="cmake -DCMAKE_EXPORT_COMPILE_COMMANDS=1 --log-level=STATUS"
CMAKE_COMMAND_THIRD_PARTY="$CMAKE_COMMAND -DCMAKE_INSTALL_PREFIX=$THIRD_PARTY_INSTALL_PREFIX"
CMAKE_COMMAND_MINIOB="$CMAKE_COMMAND"

ALL_ARGS=("$@")
BUILD_ARGS=()
MAKE_ARGS=()
MAKE=make

echo "$0 ${ALL_ARGS[@]}"

function usage
{
  echo "Usage:"
  echo "./build.sh -h"
  echo "./build.sh init # install dependence"
  echo "./build.sh clean"
  echo "./build.sh [BuildType] [--make [MakeOptions]]"
  echo ""
  echo "OPTIONS:"
  echo "BuildType => debug(default), release"
  echo "MakeOptions => Options to make command, default: -j N"

  echo ""
  echo "Examples:"
  echo "# Init."
  echo "./build.sh init"
  echo ""
  echo "# Build by debug mode and make with -j24."
  echo "./build.sh debug --make -j24"
}

function parse_args
{
  make_start=false
  for arg in "${ALL_ARGS[@]}"; do
    if [[ "$arg" == "--make" ]]
    then
      make_start=true
    elif [[ $make_start == false ]]
    then
      BUILD_ARGS+=("$arg")
    else
      MAKE_ARGS+=("$arg")
    fi

  done
}

# try call command make, if use give --make in command line.
function try_make
{
  if [[ $MAKE != false ]]
  then
    # use single thread `make` if concurrent building failed
    $MAKE "${MAKE_ARGS[@]}" || $MAKE
  fi
}

# create build directory and cd it.
function prepare_build_dir
{
  TYPE=$1
  mkdir -p $TOPDIR/build_$TYPE && cd $TOPDIR/build_$TYPE
}

function do_init
{
  git submodule update --init || return
  git -C "deps/3rd/libevent" checkout 112421c8fa4840acd73502f2ab6a674fc025de37 || return
  # git submodule update --remote "deps/3rd/libevent" || return
  git -C "deps/3rd/jsoncpp" checkout 1.9.6 || return
  current_dir=$PWD

  MAKE_COMMAND="make --silent"

  # build libevent
  cd ${TOPDIR}/deps/3rd/libevent && \
    mkdir -p build && \
    cd build && \
    ${CMAKE_COMMAND_THIRD_PARTY} .. -DEVENT__DISABLE_OPENSSL=ON -DEVENT__LIBRARY_TYPE=BOTH && \
    ${MAKE_COMMAND} -j4 && \
    make install

  # build googletest
  cd ${TOPDIR}/deps/3rd/googletest && \
    mkdir -p build && \
    cd build && \
    ${CMAKE_COMMAND_THIRD_PARTY} .. && \
    ${MAKE_COMMAND} -j4 && \
    ${MAKE_COMMAND} install

  # build google benchmark
  cd ${TOPDIR}/deps/3rd/benchmark && \
    mkdir -p build && \
    cd build && \
    ${CMAKE_COMMAND_THIRD_PARTY} .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBENCHMARK_ENABLE_TESTING=OFF  -DBENCHMARK_INSTALL_DOCS=OFF -DBENCHMARK_ENABLE_GTEST_TESTS=OFF -DBENCHMARK_USE_BUNDLED_GTEST=OFF -DBENCHMARK_ENABLE_ASSEMBLY_TESTS=OFF && \
    ${MAKE_COMMAND} -j4 && \
    ${MAKE_COMMAND} install

  # build jsoncpp
  cd ${TOPDIR}/deps/3rd/jsoncpp && \
    mkdir -p build && \
    cd build && \
    ${CMAKE_COMMAND_THIRD_PARTY} -DJSONCPP_WITH_TESTS=OFF -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF .. && \
    ${MAKE_COMMAND} -j4 && \
    ${MAKE_COMMAND} install

  # build replxx
  cd ${TOPDIR}/deps/3rd/replxx && \
    mkdir -p build && \
    cd build && \
    ${CMAKE_COMMAND_THIRD_PARTY} .. -DCMAKE_BUILD_TYPE=Release -DREPLXX_BUILD_EXAMPLES=OFF -DREPLXX_BUILD_PACKAGE=OFF && \
    ${MAKE_COMMAND} -j4 && \
    ${MAKE_COMMAND} install

  cd $current_dir
}

function do_musl_init
{
  git clone https://github.com/ronchaine/libexecinfo deps/3rd/libexecinfo || return
  current_dir=$PWD

  MAKE_COMMAND="make --silent"
  cd ${TOPDIR}/deps/3rd/libexecinfo && \
    ${MAKE_COMMAND} install && \
    ${MAKE_COMMAND} clean && rm ${TOPDIR}/deps/3rd/libexecinfo/libexecinfo.so.* && \
    cd ${current_dir}
}

function prepare_build_dir
{
  TYPE=$1
  mkdir -p ${TOPDIR}/build_${TYPE}
  rm -f build
  echo "create soft link for build_${TYPE}, linked by directory named build"
  ln -s build_${TYPE} build
  cd ${TOPDIR}/build_${TYPE}
}

function do_build
{
  TYPE=$1; shift
  prepare_build_dir $TYPE || return
  echo "${CMAKE_COMMAND_MINIOB} ${TOPDIR} $@"
  ${CMAKE_COMMAND_MINIOB} -S ${TOPDIR} $@
}

function do_clean
{
  echo "clean build_* dirs"
  find . -maxdepth 1 -type d -name 'build_*' | xargs rm -rf
}

function build {
  # 默认参数是 debug
  if [ -z "${BUILD_ARGS[0]}" ]; then
    set -- "debug"  # 如果没有参数，则设置默认值
  else
    set -- "${BUILD_ARGS[@]}"  # 否则使用 BUILD_ARGS 的第一个参数
  fi
  local build_type_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')  # 转换为小写
  echo "Build type: $build_type_lower"  # 输出构建类型

  do_build $@ -DCMAKE_BUILD_TYPE="$build_type_lower" # 调用 do_build
}


function main
{
  case "$1" in
    -h)
      usage
      ;;
    init)
      do_init
      ;;
    musl)
      do_musl_init
      ;;
    clean)
      do_clean
      ;;
    *)
      parse_args
      build
      try_make
      ;;
  esac
}

main "$@"
