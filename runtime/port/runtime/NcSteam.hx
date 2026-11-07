package port.runtime;

class NcSteam {
    static var state = 0;

    public static function open():Bool {
        if (state == 0) {
            state = try Native.steam_open() catch (_:Dynamic) -9;
            NcLog.say("steam networking: " + (state == 1 ? "ready" : "unavailable (" + state + ")"));
        }
        return state == 1;
    }

    static function cstr(s:String):hl.Bytes {
        var b = haxe.io.Bytes.ofString(s);
        var out = haxe.io.Bytes.alloc(b.length + 1);
        out.blit(0, b, 0, b.length);
        out.set(b.length, 0);
        return @:privateAccess out.b;
    }

    static function text(b:hl.Bytes, length:Int):String {
        return b == null ? null : b.toBytes(length).getString(0, length);
    }

    public static function pump():Void {
        if (open()) Native.steam_pump();
    }

    public static function status():String {
        if (!open()) return "unavailable";
        var n = 0;
        return text(Native.steam_status(n), n);
    }

    public static function link(id:String):String {
        if (!open()) return "unavailable";
        var n = 0;
        return text(Native.steam_link(cstr(id), n), n);
    }

    public static function me():{id:String, name:String} {
        if (!open()) return null;
        var n = 0;
        var parts = text(Native.steam_me(n), n).split("\t");
        return {id: parts[0], name: parts.length > 1 ? parts[1] : ""};
    }

    public static function friends():Array<{id:String, name:String, playing:Bool, online:Bool}> {
        var out = [];
        if (!open()) return out;
        var n = 0;
        var all = text(Native.steam_friends(n), n);
        if (all == null) return out;
        for (line in all.split("\n")) {
            var f = line.split("\t");
            if (f.length >= 4) out.push({id: f[0], playing: f[1] == "1", online: f[2] != "0", name: f.slice(3).join("\t")});
        }
        return out;
    }

    public static function send(id:String, data:haxe.io.Bytes, channel:Int, reliable:Bool):Int {
        if (!open()) return -1;
        return Native.steam_send(cstr(id), @:privateAccess data.b, data.length, channel, reliable);
    }

    public static function receive(channel:Int):{from:String, data:haxe.io.Bytes} {
        if (!open()) return null;
        var n = 0;
        var raw = Native.steam_receive(channel, n);
        if (raw == null) return null;
        var all = raw.toBytes(n);
        var id = haxe.Int64.toStr(haxe.Int64.make(all.getInt32(4), all.getInt32(0)));
        return {from: id, data: all.sub(8, n - 8)};
    }

    public static function avatar(id:String):{width:Int, height:Int, rgba:haxe.io.Bytes} {
        if (!open()) return null;
        var w = 0, h = 0;
        var raw = Native.steam_avatar(cstr(id), w, h);
        return raw == null ? null : {width: w, height: h, rgba: raw.toBytes(w * h * 4)};
    }

    public static function request():String {
        if (!open()) return null;
        var n = 0;
        return text(Native.steam_request(n), n);
    }

    public static function accept(id:String):Bool {
        return open() && Native.steam_accept(cstr(id));
    }

    public static function close(id:String):Bool {
        return open() && Native.steam_close(cstr(id));
    }

    public static function connection(id:String):Int {
        return open() ? Native.steam_state(cstr(id)) : -1;
    }
}

@:hlNative("ncane")
private extern class Native {
    static function steam_open():Int;
    static function steam_pump():Void;
    static function steam_status(outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_link(id:hl.Bytes, outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_me(outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_friends(outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_send(id:hl.Bytes, data:hl.Bytes, length:Int, channel:Int, reliable:Bool):Int;
    static function steam_receive(channel:Int, outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_request(outLength:hl.Ref<Int>):hl.Bytes;
    static function steam_accept(id:hl.Bytes):Bool;
    static function steam_close(id:hl.Bytes):Bool;
    static function steam_state(id:hl.Bytes):Int;
    static function steam_avatar(id:hl.Bytes, outWidth:hl.Ref<Int>, outHeight:hl.Ref<Int>):hl.Bytes;
}
