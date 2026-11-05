{{flutter_js}}
{{flutter_build_config}}

const userConfig = {
  useLocalCanvasKit: true,
  canvasKitBaseUrl: "canvaskit/"
};

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
