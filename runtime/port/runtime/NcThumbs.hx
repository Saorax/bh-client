package port.runtime;

class NcThumbs {
    static var screen:Dynamic = null;
    static var path:String = null;
    public static var last(default, null):String = null;
    static var until:Float = 0;
    static var asked:Map<String, Bool> = new Map();

    public static function shown(owner:Dynamic, wanted:String, bitmap:Dynamic):Void {
        screen = owner;
        last = wanted;
        path = wanted != null && (bitmap == null || bitmap.bitmapData == null) ? wanted : null;
        if (path == null) {
            unmask(owner);
            return;
        }
        until = haxe.Timer.stamp() + 10;
        if (!asked.exists(wanted)) {
            asked.set(wanted, true);
            try {
                ArchiveLoader.BeginStage("LevelArt");
                ArchiveLoader.QueueFileLoad(wanted, "LevelArt");
            } catch (e:Dynamic) NcLog.say("replay thumbnail: " + e);
        }
    }

    static function unmask(owner:Dynamic):Void {
        try {
            var holder:flash.display.DisplayObject = cast owner.mIconHolder.clip;
            var parent = holder.parent;
            for (i in 0...parent.numChildren) {
                var sibling = parent.getChildAt(i);
                if (sibling != holder && sibling.mask == holder) {
                    sibling.mask = null;
                    sibling.visible = false;
                }
            }
        } catch (e:Dynamic) NcLog.say("replay thumbnail: " + e);
    }

    public static function tick():Void {
        if (path == null) return;
        if (haxe.Timer.stamp() > until) {
            path = null;
            return;
        }
        var wanted = path;
        if (try GameUtil.method_792(wanted, true) == null catch (_:Dynamic) true) return;
        path = null;
        try screen.RenderLevelIcon(wanted) catch (e:Dynamic) NcLog.say("replay thumbnail: " + e);
    }
}
