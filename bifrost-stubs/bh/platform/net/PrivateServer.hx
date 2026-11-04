package bh.platform.net;

class PrivateServer {
    public static var host:String = null;
    public static var p2pDelay:UInt = 48;
    public static var p2pRelayOnly:Bool = false;
    public static var p2pSmoothing:Bool = true;
    public static var p2pSmoothingMs:Float = 100;
    public static var p2pRollback:Bool = true;
    public static var p2pDelaySet:Bool = false;

    public static function log(line:String, now:Bool = false):Void {
        bh.platform.Platform.log(line);
    }

    public static function readP2PSettings(cfg:Dynamic = null):Void {}

    public static function hold(on:Bool):Void {}
}
