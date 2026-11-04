package bh.platform.net;

class P2PChoice {
    public static function readAsk(packet:Dynamic):Array<Dynamic> {
        return [];
    }

    public static function asked(roomNumber:UInt, players:Array<Dynamic>):Void {}

    public static function warmStarts():Void {}

    public static function matchStarts(roomNumber:UInt):Void {}
}
