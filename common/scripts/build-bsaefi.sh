#!/usr/bin/env bash

# Copyright (c) 2021, ARM Limited and Contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of ARM nor the names of its contributors may be used
# to endorse or promote products derived from this software without specific
# prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

#
# This script uses the following environment variables from the variant
#
# VARIANT - build variant name
# TOP_DIR - workspace root directory
# CROSS_COMPILE - PATH to GCC including CROSS-COMPILE prefix
# PARALLELISM - number of cores to build across
# UEFI_BUILD_ENABLED - Flag to enable building UEFI
# UEFI_PATH - sub-directory containing UEFI code
# UEFI_BUILD_MODE - DEBUG or RELEASE
# UEFI_TOOLCHAIN - Toolchain supported by Linaro uefi-tools: GCC49, GCC48 or GCC47
# UEFI_PLATFORMS - List of platforms to build
# UEFI_PLAT_{platform name} - array of platform parameters:
#     - platname - the name of the platform used by the build
#     - makefile - the makefile to execute for this platform
#     - output - where to store the files in packaging phase
#     - defines - extra platform defines during the build
#     - binary - what to call the final output binary


TOP_DIR=`pwd`
. $TOP_DIR/../../common/config/common_config.cfg

UEFI_PATH=edk2
UEFI_TOOLCHAIN=GCC49
UEFI_BUILD_MODE=RELEASE
GCC=tools/gcc-linaro-${LINARO_TOOLS_VERSION}-x86_64_aarch64-linux-gnu/bin/aarch64-linux-gnu-
CROSS_COMPILE=$TOP_DIR/$GCC
UEFI_LIBC_PATH=edk2-libc
PATCH_DIR=$TOP_DIR/../patches
COMMON_PATCH_DIR=$TOP_DIR/../../common/patches

do_build()
{
    pushd $TOP_DIR/$UEFI_PATH

    git checkout ShellPkg/ShellPkg.dsc # Remove if any patches applied
    git checkout ArmPkg/Drivers/ArmGic/GicV3/ArmGicV3Dxe.c # Remove if any patches applied
    if ! patch -R -p0 -s -f --dry-run < $COMMON_PATCH_DIR/edk2_gicv3.patch; then
         echo "Applying EDK2 GICv3 Patch ..."
         patch  -p0  < $COMMON_PATCH_DIR/edk2_gicv3.patch
    fi

    if [ "$BUILD_PLAT" = "ES" ]; then
       if ! patch -R -p0 -s -f --dry-run < $PATCH_DIR/es_bsa.patch; then
         echo "Applying ES BSA Patch ..."
         patch  -p0  < $PATCH_DIR/es_bsa.patch
       fi
    elif [ "$BUILD_PLAT" = "IR" ]; then
       if ! patch -R -p0 -s -f --dry-run < $PATCH_DIR/ir_bsa.patch; then
          echo "Applying IR BSA Patch ..."
          patch  -p0  < $PATCH_DIR/ir_bsa.patch
          touch $TOP_DIR/build-scripts/ir_bsa.flag

          if grep "gEfiHiiConfigRoutingProtocolGuid" MdeModulePkg/Library/UefiHiiServicesLib/UefiHiiServicesLib.c
          then
            sed -i '/gEfiHiiConfigRoutingProtocolGuid/{N;d;}' MdeModulePkg/Library/UefiHiiServicesLib/UefiHiiServicesLib.c
            echo "gEfiHiiConfigRoutingProtocolGuid is removed"
          fi
       fi
    else
       echo "Specify platform ES or IR"
       exit_fun
    fi

    source ./edksetup.sh
    make -C BaseTools/Source/C
    export EDK2_TOOLCHAIN=$UEFI_TOOLCHAIN
    arch=$(uname -m)
    if [[ $arch = "aarch64" ]]
    then
        echo "arm64 native compile"
    else
        CROSS_COMPILE_DIR=$(dirname $CROSS_COMPILE)
        PATH="$PATH:$CROSS_COMPILE_DIR"
        export ${UEFI_TOOLCHAIN}_AARCH64_PREFIX=$CROSS_COMPILE
    fi
    local vars=
    export PACKAGES_PATH=$TOP_DIR/$UEFI_PATH:$TOP_DIR/$UEFI_PATH/$UEFI_LIBC_PATH
    export PYTHON_COMMAND=/usr/bin/python3
    source ShellPkg/Application/bsa-acs/tools/scripts/acsbuild.sh
    popd
}

do_clean()
{
    pushd $TOP_DIR/$UEFI_PATH
    CROSS_COMPILE_DIR=$(dirname $CROSS_COMPILE)
    PATH="$PATH:$CROSS_COMPILE_DIR"
    source ./edksetup.sh
    make -C BaseTools/Source/C clean
    rm -rf Build/Shell/DEBUG_GCC49
    popd
}

do_package ()
{
    echo "Packaging BSA... $VARIANT";
    # Copy binaries to output folder
    pushd $TOP_DIR
}

exit_fun() {
   exit 1 # Exit script
}

DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

BUILD_PLAT=$1

if [ -z "$BUILD_PLAT" ]
then
   echo "Specify platform ES or IR"
   exit_fun
fi

source $DIR/framework.sh $@
