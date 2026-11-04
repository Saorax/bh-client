package bh.platform.net;

class SpectateFeed {
    public static var caughtUpAt:Float = -1;

    public static function hostFrame(core:Dynamic, start:Float, through:Float):Void {}

    public static function resumeAt(core:Dynamic, start:Float, at:Float):Void {}

    public static function hostEnd(abrupt:Bool = false):Void {}
}
