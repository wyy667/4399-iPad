// Run with macOS osascript -l JavaScript; uses the OS's actual bundle parser.
ObjC.import('Foundation');
function run(args) {
  const bundle = $.NSBundle.bundleWithPath(args[0]);
  function value(object) { return object.isNil() ? null : ObjC.unwrap(object); }
  return JSON.stringify({
    path: args[0],
    identifier: value(bundle.bundleIdentifier),
    executablePath: value(bundle.executablePath),
    resourcePath: value(bundle.resourcePath)
  }, null, 2);
}
