package bh.platform;

class PlayerMenu {
    public static function entries(p:Dynamic, extra:Array<Dynamic> = null):Array<Dynamic> {
        return extra != null ? extra.copy() : [];
    }
}
