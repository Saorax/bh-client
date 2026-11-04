package bh.platform.net;

class Rejoin {
    public static var active:Bool = false;
    public static var through:Float = -1;
    public static var caughtUpAt:Float = -1;
    public static var handedBackAt:Float = -1;

    public static function handBack(at:Float):Void {}

    public static function end(why:String):Void {}

    public static function frame(core:Dynamic, start:Float):UInt {
        return 0xFFFFFFFF;
    }
}
