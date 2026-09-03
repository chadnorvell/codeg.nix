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
  version = "0.30.2";

  sources = {
    aarch64-darwin = {
      archive = "darwin-arm64";
      hash = "sha256-wF9Dap/qIdhPsWEQvlgibBFABbh8/idrUNS3kl3BBm8=";
    };
    aarch64-linux = {
      archive = "linux-arm64";
      hash = "sha256-IpoyLojrkLSpTzgvZxjKoeTlfHxD75mccOQUja14n3I=";
    };
    x86_64-linux = {
      archive = "linux-x64";
      hash = "sha256-RAkGHUM6ExVAXOGbOgY/ACaUjHxesOE4ylkGTW0xVUk=";
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
