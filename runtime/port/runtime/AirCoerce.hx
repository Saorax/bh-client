package port.runtime;

import flash.utils.ByteArray;

class AirCoerce {
    public static function forCallee(fn:Dynamic, index:Int, value:Dynamic):Dynamic {
        if (value == null || !Std.isOfType(value, flash.utils.ByteArray.ByteArrayData) || !Native.arg_is_string(fn, index))
            return value;
        var data:ByteArray = value;
        var length = data.length;
        var bytes:haxe.io.Bytes = cast value;
        var start = length >= 3 && bytes.get(0) == 0xEF && bytes.get(1) == 0xBB && bytes.get(2) == 0xBF ? 3 : 0;
        return bytes.getString(start, length - start);
    }
}

@:hlNative("ncane")
private extern class Native {
    static function arg_is_string(fn:Dynamic, index:Int):Bool;
}
