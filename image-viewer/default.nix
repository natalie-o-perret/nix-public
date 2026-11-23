{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  python3,
  quickshell,
  qt6,
  dcommon,
}:

stdenvNoCC.mkDerivation {
  pname = "dux-images";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  nativeInstallCheckInputs = [ python3 ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    qml="$out/share/dux-images"
    mkdir -p "$qml" "$out/bin" "$out/share/applications"
    cp *.qml "$qml/"
    ln -s ${dcommon}/DCommon "$qml/DCommon"
    cp tests/shell.qml "$qml/tests.qml"
    install -m755 dimages "$out/bin/dimages"
    substituteInPlace "$out/bin/dimages" \
      --replace-fail '@bash@' '${bash}/bin/bash' \
      --replace-fail '@realpath@' '${coreutils}/bin/realpath' \
      --replace-fail '@quickshell@' '${quickshell}/bin/quickshell' \
      --replace-fail '@qml@' "$qml"
    wrapProgram "$out/bin/dimages" \
      --prefix QT_PLUGIN_PATH : '${
        lib.makeSearchPath qt6.qtbase.qtPluginPrefix [
          qt6.qtimageformats
          qt6.qtsvg
        ]
      }'
    cat > "$out/share/applications/local.dux.images.desktop" <<EOF
    [Desktop Entry]
    Type=Application
    Name=Images
    Comment=Image viewer for the dux desktop
    Exec=$out/bin/dimages %f
    Icon=image-x-generic
    Terminal=false
    Categories=Graphics;Viewer;
    MimeType=image/jpeg;image/png;image/webp;image/bmp;image/svg+xml;image/tiff;image/gif;image/x-icon;
    StartupWMClass=local.dux.images
    EOF
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3}/bin/python3 tests/check.py "$out" ${quickshell}/bin/quickshell
    runHook postInstallCheck
  '';

  meta = {
    description = "A small image viewer using the shared Dux components";
    mainProgram = "dimages";
    platforms = lib.platforms.linux;
  };
}
