package bh.platform.net;

class ModCheck {
    public static var count(get, never):UInt;

    static function get_count():UInt {
        return 0;
    }

    public static function refresh():Void {}

    public static function write(b:flash.utils.ByteArray):Void {}

    public static function compare(b:flash.utils.ByteArray):String {
        return null;
    }
}
