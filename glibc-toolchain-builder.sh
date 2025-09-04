#!/bin/bash

# Fully Automated Build Script for glibc 2.34 with Complete Toolchain
# NO ROOT REQUIRED - NO USER INTERACTION - FULLY AUTOMATED
# Just run: ./build_toolchain.sh

set -e  # Exit on error

# Configuration
GLIBC_VERSION="2.34"
GCC_VERSION="11.2.0"
BINUTILS_VERSION="2.37"
GMP_VERSION="6.2.1"
MPFR_VERSION="4.1.0"
MPC_VERSION="1.2.1"
KERNEL_VERSION="5.10.70"
MAKE_VERSION="4.3"
M4_VERSION="1.4.19"
BISON_VERSION="3.8.2"
FLEX_VERSION="2.6.4"
TEXINFO_VERSION="6.8"

# Build configuration - all in user home directory
BUILD_BASE="${HOME}/glibc_build"
BUILD_DIR="${BUILD_BASE}/build_toolchain"
SOURCE_DIR="${BUILD_DIR}/sources"
WORK_DIR="${BUILD_DIR}/work"
INSTALL_PREFIX="${BUILD_DIR}/toolchain"
SYSROOT="${INSTALL_PREFIX}/sysroot"
BUILD_TOOLS="${BUILD_DIR}/build_tools"
TARGET="x86_64-linux-gnu"
JOBS=$(nproc 2>/dev/null || echo 2)
LOG_FILE="${BUILD_DIR}/build.log"
ERROR_LOG="${BUILD_DIR}/error.log"

# Set PATH to include our build tools
export PATH="${BUILD_TOOLS}/bin:${PATH}"
export LD_LIBRARY_PATH="${BUILD_TOOLS}/lib:${LD_LIBRARY_PATH}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Progress tracking
TOTAL_STEPS=12
CURRENT_STEP=0

# Print colored status
print_status() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    echo -e "${GREEN}[${CURRENT_STEP}/${TOTAL_STEPS}]${NC} ${BLUE}$1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}ERROR: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ERROR_LOG"
}

print_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

# Initialize build environment
initialize() {
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  Automated glibc 2.34 Toolchain Builder${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Build started at: $(date)"
    echo -e "Build directory: ${BLUE}${BUILD_DIR}${NC}"
    echo -e "Parallel jobs: ${BLUE}${JOBS}${NC}"
    echo -e "Log file: ${BLUE}${LOG_FILE}${NC}"
    echo ""
    
    # Create directory structure
    mkdir -p "$SOURCE_DIR"
    mkdir -p "$WORK_DIR"
    mkdir -p "$INSTALL_PREFIX"
    mkdir -p "$SYSROOT"
    mkdir -p "$BUILD_TOOLS"
    
    # Initialize log files
    echo "Build started at $(date)" > "$LOG_FILE"
    echo "Error log started at $(date)" > "$ERROR_LOG"
}

# Function to check if a command exists
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Automated prerequisite checker
check_system_requirements() {
    print_status "Checking system requirements"
    
    local missing_critical=()
    
    # Check critical requirements
    if ! check_command gcc; then
        missing_critical+=("gcc")
    fi
    
    if ! check_command g++; then
        missing_critical+=("g++")
    fi
    
    if ! check_command tar; then
        missing_critical+=("tar")
    fi
    
    if ! check_command wget && ! check_command curl; then
        missing_critical+=("wget or curl")
    fi
    
    if [ ${#missing_critical[@]} -ne 0 ]; then
        print_error "Critical requirements missing: ${missing_critical[*]}"
        print_error "These must be installed on the system. Contact your administrator."
        exit 1
    fi
    
    print_success "System requirements satisfied"
}

# Create wget wrapper if needed
setup_download_tool() {
    if ! check_command wget && check_command curl; then
        cat > "${BUILD_TOOLS}/bin/wget" << 'EOF'
#!/bin/bash
# Wrapper to use curl when wget is not available
if [[ "$1" == "-c" ]]; then
    shift
    curl -L -C - -o "$(basename "$1")" "$1"
else
    curl -L -o "$(basename "$1")" "$1"
fi
EOF
        chmod +x "${BUILD_TOOLS}/bin/wget"
        export PATH="${BUILD_TOOLS}/bin:${PATH}"
    fi
}

# Build make if not available
build_make() {
    if ! check_command make; then
        print_status "Building make (not found on system)"
        cd "$SOURCE_DIR"
        if [ ! -f "make-${MAKE_VERSION}.tar.gz" ]; then
            wget -q -c "https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz" || \
            curl -s -L -O "https://ftp.gnu.org/gnu/make/make-${MAKE_VERSION}.tar.gz"
        fi
        tar -xzf "make-${MAKE_VERSION}.tar.gz" -C "$WORK_DIR/" 2>/dev/null
        
        cd "$WORK_DIR/make-${MAKE_VERSION}"
        ./configure --prefix="$BUILD_TOOLS" --disable-nls >> "$LOG_FILE" 2>&1
        ./build.sh >> "$LOG_FILE" 2>&1
        ./make install >> "$LOG_FILE" 2>&1
        export PATH="${BUILD_TOOLS}/bin:${PATH}"
        print_success "make built successfully"
    fi
}

# Build m4 if not available
build_m4() {
    if ! check_command m4; then
        print_status "Building m4 (required for bison)"
        cd "$SOURCE_DIR"
        if [ ! -f "m4-${M4_VERSION}.tar.xz" ]; then
            wget -q -c "https://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz" || \
            curl -s -L -O "https://ftp.gnu.org/gnu/m4/m4-${M4_VERSION}.tar.xz"
        fi
        tar -xf "m4-${M4_VERSION}.tar.xz" -C "$WORK_DIR/" 2>/dev/null
        
        cd "$WORK_DIR/m4-${M4_VERSION}"
        ./configure --prefix="$BUILD_TOOLS" --disable-nls >> "$LOG_FILE" 2>&1
        make -j"$JOBS" >> "$LOG_FILE" 2>&1
        make install >> "$LOG_FILE" 2>&1
        print_success "m4 built successfully"
    fi
}

# Build bison if not available
build_bison() {
    if ! check_command bison; then
        print_status "Building bison (required for glibc)"
        cd "$SOURCE_DIR"
        if [ ! -f "bison-${BISON_VERSION}.tar.xz" ]; then
            wget -q -c "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz" || \
            curl -s -L -O "https://ftp.gnu.org/gnu/bison/bison-${BISON_VERSION}.tar.xz"
        fi
        tar -xf "bison-${BISON_VERSION}.tar.xz" -C "$WORK_DIR/" 2>/dev/null
        
        cd "$WORK_DIR/bison-${BISON_VERSION}"
        ./configure --prefix="$BUILD_TOOLS" --disable-nls >> "$LOG_FILE" 2>&1
        make -j"$JOBS" >> "$LOG_FILE" 2>&1
        make install >> "$LOG_FILE" 2>&1
        print_success "bison built successfully"
    fi
}

# Build flex if not available
build_flex() {
    if ! check_command flex; then
        print_status "Building flex (required for binutils)"
        cd "$SOURCE_DIR"
        if [ ! -f "flex-${FLEX_VERSION}.tar.gz" ]; then
            wget -q -c "https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz" || \
            curl -s -L -o "flex-${FLEX_VERSION}.tar.gz" \
                "https://github.com/westes/flex/releases/download/v${FLEX_VERSION}/flex-${FLEX_VERSION}.tar.gz"
        fi
        tar -xzf "flex-${FLEX_VERSION}.tar.gz" -C "$WORK_DIR/" 2>/dev/null
        
        cd "$WORK_DIR/flex-${FLEX_VERSION}"
        ./configure --prefix="$BUILD_TOOLS" --disable-nls >> "$LOG_FILE" 2>&1
        make -j"$JOBS" >> "$LOG_FILE" 2>&1
        make install >> "$LOG_FILE" 2>&1
        print_success "flex built successfully"
    fi
}

# Build texinfo if not available
build_texinfo() {
    if ! check_command makeinfo; then
        print_status "Building texinfo (required for binutils)"
        cd "$SOURCE_DIR"
        if [ ! -f "texinfo-${TEXINFO_VERSION}.tar.xz" ]; then
            wget -q -c "https://ftp.gnu.org/gnu/texinfo/texinfo-${TEXINFO_VERSION}.tar.xz" || \
            curl -s -L -O "https://ftp.gnu.org/gnu/texinfo/texinfo-${TEXINFO_VERSION}.tar.xz"
        fi
        tar -xf "texinfo-${TEXINFO_VERSION}.tar.xz" -C "$WORK_DIR/" 2>/dev/null
        
        cd "$WORK_DIR/texinfo-${TEXINFO_VERSION}"
        ./configure --prefix="$BUILD_TOOLS" --disable-nls >> "$LOG_FILE" 2>&1
        make -j"$JOBS" >> "$LOG_FILE" 2>&1
        make install >> "$LOG_FILE" 2>&1
        print_success "texinfo built successfully"
    fi
}

# Build all prerequisites
build_prerequisites() {
    print_status "Building prerequisites if needed"
    setup_download_tool
    build_make
    build_m4
    build_bison
    build_flex
    build_texinfo
}

# Download sources with progress indication
download_sources() {
    print_status "Downloading source packages"
    cd "$SOURCE_DIR"
    
    local sources=(
        "https://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.xz"
        "https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VERSION}/gcc-${GCC_VERSION}.tar.xz"
        "https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz"
        "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.xz"
        "https://ftp.gnu.org/gnu/mpfr/mpfr-${MPFR_VERSION}.tar.xz"
        "https://ftp.gnu.org/gnu/mpc/mpc-${MPC_VERSION}.tar.gz"
        "https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${KERNEL_VERSION}.tar.xz"
    )
    
    local count=1
    local total=${#sources[@]}
    
    for url in "${sources[@]}"; do
        local file=$(basename "$url")
        if [ ! -f "$file" ]; then
            echo -e "  ${BLUE}[${count}/${total}]${NC} Downloading ${file}..."
            if check_command wget; then
                wget -q -c "$url" 2>> "$ERROR_LOG"
            else
                curl -s -L -O "$url" 2>> "$ERROR_LOG"
            fi
        else
            echo -e "  ${GREEN}[${count}/${total}]${NC} ${file} already exists, skipping"
        fi
        count=$((count + 1))
    done
    
    # Extract all archives
    echo -e "  ${BLUE}Extracting archives...${NC}"
    for archive in *.tar.*; do
        if [ -f "$archive" ]; then
            tar -xf "$archive" -C "$WORK_DIR/" 2>/dev/null || true
        fi
    done
    
    print_success "All sources downloaded and extracted"
}

# Build Linux kernel headers
build_linux_headers() {
    print_status "Building Linux kernel headers"
    cd "$WORK_DIR/linux-${KERNEL_VERSION}"
    
    make -s ARCH=x86_64 INSTALL_HDR_PATH="$SYSROOT/usr" headers_install >> "$LOG_FILE" 2>&1
    print_success "Linux headers installed"
}

# Build binutils
build_binutils() {
    print_status "Building binutils (assembler, linker, etc.)"
    mkdir -p "$WORK_DIR/build-binutils"
    cd "$WORK_DIR/build-binutils"
    
    LDFLAGS="-Wl,-rpath,${INSTALL_PREFIX}/lib" \
    "$WORK_DIR/binutils-${BINUTILS_VERSION}/configure" \
        --prefix="$INSTALL_PREFIX" \
        --target="$TARGET" \
        --with-sysroot="$SYSROOT" \
        --disable-nls \
        --disable-werror \
        --enable-gold \
        --enable-ld=default \
        --enable-plugins \
        --enable-threads \
        --enable-deterministic-archives \
        --disable-gdb \
        --disable-sim >> "$LOG_FILE" 2>&1
    
    make -j"$JOBS" >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    print_success "Binutils built and installed"
}

# Build GCC stage 1
build_gcc_stage1() {
    print_status "Building GCC stage 1 (bootstrap compiler)"
    
    # Setup GCC prerequisites
    cd "$WORK_DIR/gcc-${GCC_VERSION}"
    ln -sf "../gmp-${GMP_VERSION}" gmp 2>/dev/null
    ln -sf "../mpfr-${MPFR_VERSION}" mpfr 2>/dev/null
    ln -sf "../mpc-${MPC_VERSION}" mpc 2>/dev/null
    
    mkdir -p "$WORK_DIR/build-gcc-stage1"
    cd "$WORK_DIR/build-gcc-stage1"
    
    LDFLAGS="-Wl,-rpath,${INSTALL_PREFIX}/lib" \
    "$WORK_DIR/gcc-${GCC_VERSION}/configure" \
        --prefix="$INSTALL_PREFIX" \
        --target="$TARGET" \
        --with-sysroot="$SYSROOT" \
        --with-newlib \
        --without-headers \
        --enable-languages=c,c++ \
        --disable-nls \
        --disable-shared \
        --disable-multilib \
        --disable-decimal-float \
        --disable-threads \
        --disable-libatomic \
        --disable-libgomp \
        --disable-libquadmath \
        --disable-libssp \
        --disable-libvtv \
        --disable-libstdcxx \
        --enable-initfini-array >> "$LOG_FILE" 2>&1
    
    make -j"$JOBS" all-gcc all-target-libgcc >> "$LOG_FILE" 2>&1
    make install-gcc install-target-libgcc >> "$LOG_FILE" 2>&1
    print_success "GCC stage 1 complete"
}

# Build glibc
build_glibc() {
    print_status "Building glibc 2.34 (C library)"
    mkdir -p "$WORK_DIR/build-glibc"
    cd "$WORK_DIR/build-glibc"
    
    # Set build environment
    export BUILD_CC="gcc"
    export CC="${INSTALL_PREFIX}/bin/${TARGET}-gcc"
    export CXX="${INSTALL_PREFIX}/bin/${TARGET}-g++"
    export AR="${INSTALL_PREFIX}/bin/${TARGET}-ar"
    export RANLIB="${INSTALL_PREFIX}/bin/${TARGET}-ranlib"
    
    "$WORK_DIR/glibc-${GLIBC_VERSION}/configure" \
        --prefix="/usr" \
        --host="$TARGET" \
        --with-headers="$SYSROOT/usr/include" \
        --enable-kernel=3.2 \
        --enable-shared \
        --enable-static-nss \
        --disable-profile \
        --disable-werror \
        --without-selinux \
        --enable-bind-now \
        --enable-stack-protector=strong \
        libc_cv_slibdir=/lib64 >> "$LOG_FILE" 2>&1
    
    make -j"$JOBS" >> "$LOG_FILE" 2>&1
    make install DESTDIR="$SYSROOT" >> "$LOG_FILE" 2>&1
    
    # Fix library paths
    mkdir -p "$SYSROOT/lib"
    ln -sfv ../lib64/ld-linux-x86-64.so.2 "$SYSROOT/lib/ld-linux-x86-64.so.2" 2>/dev/null
    
    print_success "glibc 2.34 built and installed"
}

# Build GCC stage 2
build_gcc_stage2() {
    print_status "Building GCC stage 2 (full compiler with C++)"
    mkdir -p "$WORK_DIR/build-gcc-stage2"
    cd "$WORK_DIR/build-gcc-stage2"
    
    LDFLAGS="-Wl,-rpath,${INSTALL_PREFIX}/lib" \
    "$WORK_DIR/gcc-${GCC_VERSION}/configure" \
        --prefix="$INSTALL_PREFIX" \
        --target="$TARGET" \
        --with-sysroot="$SYSROOT" \
        --enable-languages=c,c++ \
        --enable-shared \
        --enable-threads=posix \
        --enable-checking=release \
        --enable-__cxa_atexit \
        --enable-gnu-unique-object \
        --enable-linker-build-id \
        --enable-initfini-array \
        --disable-libunwind-exceptions \
        --enable-gnu-indirect-function \
        --enable-lto \
        --disable-nls \
        --disable-multilib \
        --with-default-libstdcxx-abi=new \
        --enable-libstdcxx-time=yes \
        --enable-libstdcxx-threads >> "$LOG_FILE" 2>&1
    
    make -j"$JOBS" >> "$LOG_FILE" 2>&1
    make install >> "$LOG_FILE" 2>&1
    print_success "Full GCC toolchain complete"
}

# Create wrapper scripts and documentation
create_wrapper_scripts() {
    print_status "Creating wrapper scripts and documentation"
    
    # Create activation script
    cat > "$INSTALL_PREFIX/activate.sh" << 'EOF'
#!/bin/bash
# Activation script for portable toolchain

TOOLCHAIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set up paths
export PATH="$TOOLCHAIN_ROOT/bin:$PATH"
export LD_LIBRARY_PATH="$TOOLCHAIN_ROOT/lib:$TOOLCHAIN_ROOT/lib64:$TOOLCHAIN_ROOT/sysroot/lib:$TOOLCHAIN_ROOT/sysroot/lib64:$LD_LIBRARY_PATH"

# Set up compiler environment
export CC="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-gcc"
export CXX="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-g++"
export AR="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-ar"
export AS="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-as"
export LD="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-ld"
export RANLIB="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-ranlib"
export NM="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-nm"
export STRIP="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-strip"
export OBJCOPY="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-objcopy"
export OBJDUMP="$TOOLCHAIN_ROOT/bin/x86_64-linux-gnu-objdump"

# Set up RPATH for compiled programs
export LDFLAGS="-Wl,-rpath,$TOOLCHAIN_ROOT/lib -Wl,-rpath,$TOOLCHAIN_ROOT/sysroot/lib64"

echo "======================================="
echo "Toolchain activated!"
echo "======================================="
echo "Installation path: $TOOLCHAIN_ROOT"
echo "GCC version: $($CC --version | head -n1)"
echo "GLIBC: $(strings $TOOLCHAIN_ROOT/sysroot/lib64/libc.so.6 | grep 'GNU C Library' | head -n1)"
echo "Binutils: $($LD --version | head -n1)"
echo "======================================="
echo ""
echo "Example usage:"
echo "  \$CC test.c -o test"
echo "  ./test"
echo ""
EOF
    
    chmod +x "$INSTALL_PREFIX/activate.sh"
    
    # Create test program
    cat > "$INSTALL_PREFIX/test.c" << 'EOF'
#include <stdio.h>
#include <features.h>
#include <gnu/libc-version.h>

int main() {
    printf("=== Custom Toolchain Test ===\n");
    printf("Hello from custom toolchain!\n");
    printf("GLIBC version: %s\n", gnu_get_libc_version());
    printf("GLIBC release: %s\n", gnu_get_libc_release());
    printf("Compiler: GCC %d.%d.%d\n", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
    
    #ifdef __x86_64__
    printf("Architecture: x86_64\n");
    #endif
    
    printf("=== Test passed! ===\n");
    return 0;
}
EOF
    
    # Create deployment script
    cat > "$INSTALL_PREFIX/deploy.sh" << 'EOF'
#!/bin/bash
# Quick deployment script
echo "Deploying toolchain..."
source "$(dirname "${BASH_SOURCE[0]}")/activate.sh"
echo "Testing installation..."
$CC "$(dirname "${BASH_SOURCE[0]}")/test.c" -o /tmp/toolchain_test
/tmp/toolchain_test && rm /tmp/toolchain_test
echo "Deployment complete!"
EOF
    chmod +x "$INSTALL_PREFIX/deploy.sh"
    
    # Create README
    cat > "$INSTALL_PREFIX/README.md" << 'EOF'
# Portable glibc 2.34 Toolchain

## Quick Start
```bash
source activate.sh
$CC your_program.c -o your_program
./your_program
```

## Quick Test
```bash
./deploy.sh
```

## Contents
- glibc 2.34
- GCC 11.2.0
- binutils 2.37
- Full C/C++ development environment

## Files
- `activate.sh` - Set up environment
- `deploy.sh` - Quick test deployment
- `test.c` - Test program
- `bin/` - All executables
- `lib*/` - All libraries
- `sysroot/` - Target system files
EOF
}

# Package the toolchain
package_toolchain() {
    print_status "Packaging toolchain"
    cd "$BUILD_DIR"
    
    # Strip binaries to reduce size
    echo -e "  ${BLUE}Stripping binaries to reduce size...${NC}"
    find "$INSTALL_PREFIX" -type f -executable -exec file {} \; 2>/dev/null | \
        grep 'ELF.*executable\|ELF.*shared object' | \
        cut -d: -f1 | \
        while read f; do
            strip --strip-unneeded "$f" 2>/dev/null || true
        done
    
    # Create both tar.gz and zip if possible
    echo -e "  ${BLUE}Creating archives...${NC}"
    
    # Always create tar.gz (tar is required)
    tar -czf "glibc-${GLIBC_VERSION}-toolchain.tar.gz" toolchain/
    ARCHIVE_SIZE=$(du -sh "glibc-${GLIBC_VERSION}-toolchain.tar.gz" | cut -f1)
    print_success "Created glibc-${GLIBC_VERSION}-toolchain.tar.gz (${ARCHIVE_SIZE})"
    
    # Create zip if available
    if check_command zip; then
        zip -qr "glibc-${GLIBC_VERSION}-toolchain.zip" toolchain/
        ZIP_SIZE=$(du -sh "glibc-${GLIBC_VERSION}-toolchain.zip" | cut -f1)
        print_success "Created glibc-${GLIBC_VERSION}-toolchain.zip (${ZIP_SIZE})"
    fi
}

# Automatic cleanup to save space
auto_cleanup() {
    echo -e "${YELLOW}Cleaning up build files to save space...${NC}"
    
    # Remove work directory (build files)
    rm -rf "$WORK_DIR"
    
    # Optionally remove source archives (comment out to keep)
    # rm -rf "$SOURCE_DIR"
    
    # Remove build tools if everything succeeded
    rm -rf "$BUILD_TOOLS"
    
    SAVED_SPACE="~8GB"
    print_success "Cleanup complete, saved ${SAVED_SPACE} of disk space"
}

# Create final summary
create_summary() {
    local SUMMARY_FILE="${BUILD_DIR}/DEPLOYMENT_INSTRUCTIONS.txt"
    
    cat > "$SUMMARY_FILE" << EOF
================================================================================
                     GLIBC 2.34 TOOLCHAIN BUILD COMPLETE
================================================================================

BUILD SUMMARY:
- Build completed: $(date)
- Build directory: ${BUILD_DIR}
- Toolchain location: ${INSTALL_PREFIX}
- Archive(s) created: 
  * glibc-${GLIBC_VERSION}-toolchain.tar.gz
EOF

    if [ -f "${BUILD_DIR}/glibc-${GLIBC_VERSION}-toolchain.zip" ]; then
        echo "  * glibc-${GLIBC_VERSION}-toolchain.zip" >> "$SUMMARY_FILE"
    fi

    cat >> "$SUMMARY_FILE" << EOF

DEPLOYMENT INSTRUCTIONS:

1. COPY TO TARGET MACHINE (e.g., EC2):
   scp ${BUILD_DIR}/glibc-${GLIBC_VERSION}-toolchain.tar.gz user@target-host:~/

2. ON TARGET MACHINE:
   tar -xzf glibc-${GLIBC_VERSION}-toolchain.tar.gz
   cd toolchain
   source activate.sh

3. TEST INSTALLATION:
   \$CC test.c -o test
   ./test

4. OR USE QUICK DEPLOY:
   cd toolchain
   ./deploy.sh

ENVIRONMENT VARIABLES SET BY activate.sh:
- CC, CXX: C and C++ compilers
- AS, LD, AR, NM: Binary utilities
- PATH: Updated to include toolchain
- LD_LIBRARY_PATH: Updated for libraries

USAGE EXAMPLES:
- Compile C: \$CC program.c -o program
- Compile C++: \$CXX program.cpp -o program
- Direct: /path/to/toolchain/bin/x86_64-linux-gnu-gcc program.c

================================================================================
EOF
    
    # Display summary
    echo ""
    cat "$SUMMARY_FILE"
    echo ""
    echo -e "${GREEN}Summary saved to: ${SUMMARY_FILE}${NC}"
}

# Error handler
error_handler() {
    local line_no=$1
    local exit_code=$2
    print_error "Build failed at line ${line_no} with exit code ${exit_code}"
    print_error "Check error log: ${ERROR_LOG}"
    print_error "Check build log: ${LOG_FILE}"
    echo ""
    echo "Common issues:"
    echo "  - Out of disk space (need ~10GB free)"
    echo "  - Network issues downloading sources"
    echo "  - Missing system compiler (gcc/g++)"
    echo ""
    exit $exit_code
}

# Set error trap
trap 'error_handler $LINENO $?' ERR

# Main execution
main() {
    # Start timer
    START_TIME=$(date +%s)
    
    # Initialize
    initialize
    
    # Check system
    check_system_requirements
    
    # Build everything
    build_prerequisites
    download_sources
    build_linux_headers
    build_binutils
    build_gcc_stage1
    build_glibc
    build_gcc_stage2
    create_wrapper_scripts
    package_toolchain
    
    # Cleanup
    auto_cleanup
    
    # Calculate build time
    END_TIME=$(date +%s)
    BUILD_TIME=$((END_TIME - START_TIME))
    BUILD_MINUTES=$((BUILD_TIME / 60))
    BUILD_SECONDS=$((BUILD_TIME % 60))
    
    # Success message
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}        BUILD COMPLETED SUCCESSFULLY!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo -e "Total build time: ${BUILD_MINUTES} minutes ${BUILD_SECONDS} seconds"
    echo ""
    
    # Create and show summary
    create_summary
    
    print_success "All done! Toolchain ready for deployment."
}

# Run the build
main "$@"