{
  autoPatchelfHook,
  fetchzip,
  lib,
  openssl,
  stdenv,
  stdenvNoCC,
  xz,
}:

let
  version = "0.30.3";

  sources = {
    aarch64-darwin = {
      archive = "darwin-arm64";
      hash = "sha256-an41gi6FGRt0vHrbVhTRRUE5kIZIJ4tW9rTTaeE9wmQ=";
    };
    aarch64-linux = {
      archive = "linux-arm64";
      hash = "sha256-JUeote/U93ZVko+0qIxTvxsu6DY1W9ySSz9AzCn/DV4=";
    };
    x86_64-linux = {
      archive = "linux-x64";
      hash = "sha256-47ma/PJdpr0Mz3p+BpUeootCjM1K/Vyo0A87ZMzDmeE=";
    };
  };

  inherit (stdenv.hostPlatform) system;
  source = sources.${system} or (throw "codeg-server: not packaged for ${system}");
in
stdenvNoCC.mkDerivation {
  pname = "codeg-server";
  inherit version;

  src = fetchzip {
    url = "https://github.com/xintaofei/codeg/releases/download/v${version}/codeg-server-${source.archive}.tar.gz";
    inherit (source) hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  buildInputs = [
    openssl
    stdenv.cc.cc.lib
    xz
  ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 codeg-server codeg-mcp -t $out/bin
    mkdir -p $out/share/codeg
    cp -R web $out/share/codeg/

    runHook postInstall
  '';

  meta = {
    description = "Headless server for the Codeg multi-agent coding workspace";
    homepage = "https://docs.codeg.app";
    license = lib.licenses.asl20;
    mainProgram = "codeg-server";
    platforms = builtins.attrNames sources;
  };
}
