package port.runtime;

class NcLog {
    public static var log:String->Void = null;

    public static function say(text:Dynamic):Void {
        if (log != null && text != null) log(Std.string(text));
    }
}
