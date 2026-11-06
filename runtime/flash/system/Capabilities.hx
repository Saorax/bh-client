package flash.system;

@:final class Capabilities {
    public static var avHardwareDisable(default, null) = true;
    public static var hasAccessibility(default, null) = false;
    public static var hasAudio(default, null) = true;
    public static var hasAudioEncoder(default, null) = false;
    public static var hasEmbeddedVideo(default, null) = false;
    public static var hasIME(default, null) = false;
    public static var hasMP3(default, null) = false;
    public static var hasPrinting(default, null) = false;
    public static var hasScreenBroadcast(default, null) = false;
    public static var hasScreenPlayback(default, null) = false;
    public static var hasStreamingAudio(default, null) = false;
    public static var hasStreamingVideo(default, null) = false;
    public static var hasTLS(default, null) = true;
    public static var hasVideoEncoder(default, null) = false;
    public static var isDebugger(default, null) = false;
    public static var isEmbeddedInAcrobat(default, null) = false;
    public static var localFileReadDisable(default, null) = false;
    public static var maxLevelIDC(default, null) = 0;
    public static var playerType(default, null) = "Desktop";
    public static var screenColor(default, null) = "color";
    public static var serverString(default, null) = "";
    public static var supports32BitProcesses(default, null) = true;
    public static var supports64BitProcesses(default, null) = true;
    public static var touchscreenType(default, null) = flash.system.TouchscreenType.FINGER;

    public static var cpuArchitecture(get, never):String;
    public static var language(get, never):String;
    public static var manufacturer(get, never):String;
    public static var os(get, never):String;
    public static var pixelAspectRatio(get, never):Float;
    public static var screenDPI(get, never):Float;
    public static var screenResolutionX(get, never):Float;
    public static var screenResolutionY(get, never):Float;
    public static var version(get, never):String;

    public static function hasMultiChannelAudio(type:String):Bool {
        return false;
    }

    static function get_cpuArchitecture():String {
        return "x86";
    }

    static function get_language():String {
        return "en";
    }

    static function get_manufacturer():String {
        return "Adobe Windows";
    }

    static function get_os():String {
        return port.runtime.NcWindow.osName();
    }

    static function get_pixelAspectRatio():Float {
        return 1;
    }

    static function get_screenDPI():Float {
        return port.runtime.NcWindow.screenDpi();
    }

    static function get_screenResolutionX():Float {
        return port.runtime.NcWindow.primaryScreen().width;
    }

    static function get_screenResolutionY():Float {
        return port.runtime.NcWindow.primaryScreen().height;
    }

    static function get_version():String {
        return port.runtime.NcWindow.airVersion();
    }
}
