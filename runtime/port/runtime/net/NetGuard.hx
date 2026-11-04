package port.runtime.net;

class NetGuard {
    public static var log:String->Void = null;
    public static var refusals:Int = 0;
    public static var connections:Int = 0;

    public static inline var CONFIG_NAME = "new-client.json";

    public static var offline:Bool = #if sys Sys.getEnv("NC_OFFLINE") == "1" #else false #end;

    public static function hasEndpoint():Bool {
        return false;
    }

    public static function official(name:String):Bool {
        return false;
    }

    public static function allowHost(name:String, remotePort:Int):Bool {
        if (name == null || name == "") return false;
        if (offline) return false;
        connections++;
        if (log != null && connections <= 50) log("network: " + name + ":" + remotePort);
        return true;
    }

    public static function allowPeer(name:String, remotePort:Int):Bool {
        return !offline && name != null && name != "";
    }

    public static function allowUrl(url:String):Bool {
        if (!offline || url == null) return true;
        var u = StringTools.trim(url).toLowerCase();
        return !(StringTools.startsWith(u, "http:") || StringTools.startsWith(u, "https:"));
    }

    public static function refuse(what:String):Void {
        refusals++;
        if (log != null && refusals <= 50) log("network: refused " + what);
    }

    public static function useEndpoint(name:String, remotePort:Int):Void {}

    public static function reload():Void {}
}
