{{flutter_js}}
{{flutter_build_config}}

const userConfig = {
  useLocalCanvasKit: true,
  canvasKitBaseUrl: "canvaskit/"
};

(function () {
  var bv = window.__SECURGYM_BUILD_VERSION__;
  if (bv && window._flutter && _flutter.buildConfig && Array.isArray(_flutter.buildConfig.builds)) {
    _flutter.buildConfig.builds.forEach(function (b) {
      if (b && b.mainJsPath && String(b.mainJsPath).indexOf('?') === -1) {
        b.mainJsPath = b.mainJsPath + '?v=' + encodeURIComponent(bv);
      }
    });
  }
})();

_flutter.loader.load({
  config: userConfig,
  serviceWorkerSettings: null,
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine(userConfig);
    await appRunner.runApp();
    const splash = document.getElementById('securgym-splash-screen');
    if (splash) {
      splash.classList.add('fade-out');
      setTimeout(function() {
        if (splash && splash.parentNode) {
          splash.remove();
        }
      }, 400);
    }
  }
});
