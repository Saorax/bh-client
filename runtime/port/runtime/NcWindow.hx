package port.runtime;

class NcWindow {
    static var events = new flash.events.EventDispatcher();
    static var shared:Dynamic = null;
    static var hooked = false;
    static var focused:Null<Bool> = null;
    static var frames = 0;
    static var airVer:String = null;

    public static function get():Dynamic {
        if (shared == null) shared = {
            width: 0,
            height: 0,
            addEventListener: function(type:Dynamic, listener:Dynamic):Void listen(type, listener),
            maximize: function():Void later(true),
            restore: function():Void later(false),
            notifyUser: function(type:Dynamic):Void Native.window_flash()
        };
        return shared;
    }

    public static function resize(width:Int, height:Int):Void {
        hxd.Window.getInstance().resize(width, height);
    }

    public static function focus(on:Bool):Void {
        if (focused == on) return;
        focused = on;
        @:privateAccess port.engine.FrameLoop.broadcast(on ? "activate" : "deactivate");
    }

    public static function tick():Void {
        if (focused != null || ++frames < 300) return;
        focus(Native.window_foreground());
    }

    public static function osName():String {
        var version = Native.os_version();
        var major = (version >> 24) & 0xFF;
        var minor = (version >> 16) & 0xFF;
        var build = version & 0xFFFF;
        if (major == 10) return build >= 22000 ? "Windows 11" : "Windows 10";
        if (major == 6 && minor == 3) return "Windows 8.1";
        if (major == 6 && minor == 2) return "Windows 8";
        if (major == 6 && minor == 1) return "Windows 7";
        return "Windows";
    }

    public static function screenDpi():Float {
        return Native.screen_dpi();
    }

    public static function airVersion():String {
        if (airVer != null) return airVer;
        var prefix = Sys.systemName() == "Mac" ? "MAC" : Sys.systemName() == "Linux" ? "LNX" : "WIN";
        try {
            var fp = port.runtime.services.NativeAne.fingerprintFolder(port.runtime.services.Launch.applicationDirectory());
            var dll = fp + "/Adobe AIR/Versions/1.0/Adobe AIR.dll";
            var n = 0;
            var bytes = Native.file_version(@:privateAccess dll.toUtf8(), n);
            if (bytes != null && n > 0) {
                airVer = prefix + " " + bytes.toBytes(n).getString(0, n);
                return airVer;
            }
        } catch (e:Dynamic) {}
        airVer = prefix + " 51,1,1,4";
        return airVer;
    }

    public static function primaryScreen():{width:Int, height:Int} {
        return {width: Native.screen_width(), height: Native.screen_height()};
    }

    public static function clipboardBitmap(data:Dynamic):Bool {
        var bitmap:flash.display.BitmapData = Std.downcast(data, flash.display.BitmapData);
        if (bitmap == null || bitmap.width <= 0 || bitmap.height <= 0) return false;
        return Native.clipboard_bitmap(bitmap.pixels.getData().bytes, bitmap.width, bitmap.height);
    }

    public static function documentsDirectory():Null<String> {
        var n = 0;
        var bytes = Native.documents_directory(n);
        return bytes != null && n > 0 ? bytes.toBytes(n).getString(0, n) : null;
    }

    public static function redirected(from:String, location:String):String {
        var lower = location.toLowerCase();
        if (StringTools.startsWith(lower, "http://") || StringTools.startsWith(lower, "https://")) return location;
        var scheme = from.indexOf("://");
        if (scheme < 0) return location;
        var hostEnd = from.indexOf("/", scheme + 3);
        var origin = hostEnd < 0 ? from : from.substr(0, hostEnd);
        if (StringTools.startsWith(location, "//")) return from.substr(0, scheme + 1) + location;
        if (StringTools.startsWith(location, "/")) return origin + location;
        var path = hostEnd < 0 ? "/" : from.substr(hostEnd);
        var query = path.indexOf("?");
        if (query >= 0) path = path.substr(0, query);
        return origin + path.substr(0, path.lastIndexOf("/") + 1) + location;
    }

    static function listen(type:String, listener:Dynamic):Void {
        events.addEventListener(type, listener);
        if (type == flash.events.Event.CLOSING && !hooked) {
            hooked = true;
            hxd.Window.getInstance().onClose = closing;
        }
    }

    static function later(maximize:Bool):Void {
        port.runtime.services.Pump.add(() -> {
            var window = hxd.Window.getInstance();
            if (window.displayMode == hxd.Window.DisplayMode.Windowed && port.engine.Display.settings.displayMode == "game") {
                if (maximize) @:privateAccess window.window.maximize();
                else @:privateAccess window.window.restore();
            }
            return false;
        });
    }

    static function closing():Bool {
        var event = new flash.events.Event(flash.events.Event.CLOSING, false, true);
        try events.dispatchEvent(event) catch (e:Dynamic) NcLog.say("window closing: " + e);
        if (event.isDefaultPrevented()) return false;
        flash.desktop.NativeApplication.nativeApplication.exit();
        return true;
    }
}

@:hlNative("ncane")
private extern class Native {
    static function window_flash():Void;
    static function window_foreground():Bool;
    static function os_version():Int;
    static function screen_dpi():Int;
    static function screen_width():Int;
    static function screen_height():Int;
    static function clipboard_bitmap(pixels:hl.Bytes, width:Int, height:Int):Bool;
    static function documents_directory(outLength:hl.Ref<Int>):hl.Bytes;
    static function file_version(path:hl.Bytes, outLength:hl.Ref<Int>):hl.Bytes;
}
