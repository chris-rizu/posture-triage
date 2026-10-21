// A three.js scene packaged as one HTML asset: WebView on the phone, iframe in the browser.
export 'scene_host_stub.dart'
    if (dart.library.js_interop) 'scene_host_web.dart'
    if (dart.library.io) 'scene_host_mobile.dart';
