{ lib
, stdenv
, python3
, libffi
, git
, cmake
, zlib
, fetchgit
, fetchFromGitHub
, makeWrapper
, runCommand
, llvmPackages_9
, glibc
, ncurses
}:

let
  unwrapped = stdenv.mkDerivation rec {
    pname = "cling-unwrapped";
    version = "0.9";

    src = fetchgit {
      url = "http://root.cern/git/clang.git";
      rev = "cling-v0.9";
      sha256 = "sha256-ft1NUIclSiZ9lN3Z3DJCWA0U9q/K1M0TKkZr+PjsFYk=";
    };
    # src = /home/tom/tools/clang;

    clingSrc = fetchFromGitHub {
      owner = "root-project";
      repo = "cling";
      rev = "v0.9";
      sha256 = "0wx3fi19wfjcph5kclf8108i436y79ddwakrcf0lgxnnxhdjyd29";
    };
    # clingSrc = /home/tom/tools/cling;

    llvmSrc = fetchgit {
      url = "http://root.cern/git/llvm.git";
      rev = "cling-v0.9";
      sha256 = "sha256-jts7DMnXwZF/pzUfWEQeJmj5XlOb51aXn6KExMbmcXg=";
    };
    # llvmSrc = /home/tom/tools/llvm;

    prePatch = ''
      echo "add_llvm_external_project(cling)" >> tools/CMakeLists.txt

      cp -r $clingSrc ./tools/cling
      chmod -R a+w ./tools/cling

      mkdir ./interpreter
      cp -r $llvmSrc ./interpreter/llvm
      chmod -R a+w ./interpreter/llvm
    '';

    patches = [
      # Applied to clang src
      ./no-clang-cpp.patch

      # Applied to cling src
      ./use-patched-llvm.patch
    ];

    nativeBuildInputs = [ python3 git cmake llvmPackages_9.llvm.dev ];
    buildInputs = [ libffi llvmPackages_9.llvm zlib ncurses ];

    strictDeps = true;

    cmakeFlags = [
      "-DLLVM_TARGETS_TO_BUILD=host;NVPTX"
      "-DLLVM_ENABLE_RTTI=ON"

      # Setting -DCLING_INCLUDE_TESTS=ON causes the cling/tools targets to be built;
      # see cling/tools/CMakeLists.txt
      "-DCLING_INCLUDE_TESTS=ON"
      "-DCLANG-TOOLS=OFF"
      # "--trace-expand"
    ];

    meta = with lib; {
      description = "The Interactive C++ Interpreter";
      homepage = "https://root.cern/cling/";
      license = with licenses; [ lgpl21 ncsa ];
      maintainers = with maintainers; [ thomasjm ];
      platforms = platforms.unix;
    };
  };

  # The flags passed to the wrapped cling should
  # a) prevent it from searching for system include files and libs, and
  # b) provide it with the include files and libs it needs (C and C++ standard library)

  # These are also exposed as cling.flags/cling.compilerIncludeFlags because it's handy to be
  # able to pass them to tools that wrap Cling, particularly Jupyter kernels such as xeus-cling
  # and the built-in jupyter-cling-kernel. Both of these use Cling as a library by linking against
  # libclingJupyter.so, so the makeWrapper approach to wrapping the binary doesn't work.
  # Thus, if you're packaging a Jupyter kernel, you either need to pass these flags as extra
  # args to xcpp (for xeus-cling) or put them in the environment variable CLING_OPTS
  # (for jupyter-cling-kernel)
  flags = [
    "-nostdinc"
    "-nostdinc++"
    "-isystem" "${lib.getDev stdenv.cc.libc}/include"
    "-I" "${lib.getDev unwrapped}/include"
    "-I" "${lib.getLib unwrapped}/lib/clang/5.0.2/include"
  ];

  # Autodetect the include paths for the compiler used to build Cling, in the same way Cling does at
  # https://github.com/root-project/cling/blob/v0.7/lib/Interpreter/CIFactory.cpp#L107:L111
  # Note: it would be nice to just put the compiler in Cling's PATH and let it do this by itself, but
  # unfortunately passing -nostdinc/-nostdinc++ disables Cling's autodetection logic.
  compilerIncludeFlags = runCommand "compiler-include-flags.txt" {} ''
    export LC_ALL=C
    ${stdenv.cc}/bin/c++ -xc++ -E -v /dev/null 2>&1 | sed -n -e '/^.include/,''${' -e '/^ \/.*++/p' -e '}' > tmp
    sed -e 's/^/-isystem /' -i tmp
    tr '\n' ' ' < tmp > $out
  '';

in

runCommand "cling-${unwrapped.version}" {
  nativeBuildInputs = [ makeWrapper ];
  inherit unwrapped flags compilerIncludeFlags;
  inherit (unwrapped) meta;
} ''
  makeWrapper $unwrapped/bin/cling $out/bin/cling \
    --add-flags "$(cat "$compilerIncludeFlags")" \
    --add-flags "$flags"
''
