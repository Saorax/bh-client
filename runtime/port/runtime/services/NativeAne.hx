package port.runtime.services;

import port.runtime.services.Extensions.ExtensionImpl;

class NativeAne extends ExtensionImpl {
    public static var log:String->Void = null;

    static inline var BYTES = 7;

    static var open:Map<Int, NativeAne> = new Map();
    static var pumping = false;

    var handle:Int;
    var id:String;
    var workDir:String;

    function new(handle:Int, id:String, workDir:String) {
        super();
        this.handle = handle;
        this.id = id;
        this.workDir = workDir;
    }

    public static function fingerprintFolder(appDir:String):String {
        var view = Sys.getEnv("BH_NC_VIEW");
        return view != null && view != "" && sys.FileSystem.isDirectory(view) ? view : appDir;
    }

    static function inFolder<T>(folder:String, run:() -> T):T {
        var before = Sys.getCwd();
        Sys.setCwd(folder);
        var result = try run() catch (error:Dynamic) {
            Sys.setCwd(before);
            throw error;
        }
        Sys.setCwd(before);
        return result;
    }

    public static function load(appDir:String, id:String, initializer:String, finalizer:String, fingerprinted = true):Null<NativeAne> {
        var dll = appDir + "/META-INF/AIR/extensions/" + id + "/META-INF/ANE/Windows-x86-64/" + id + ".dll";
        if (!sys.FileSystem.exists(dll)) {
            say("extension " + id + ": no DLL at " + dll);
            return null;
        }
        var folder = fingerprinted ? fingerprintFolder(appDir) : appDir;
        var handle = try inFolder(folder, () -> Native.load(@:privateAccess dll.toUtf8(), @:privateAccess appDir.toUtf8(),
            @:privateAccess initializer.toUtf8(), @:privateAccess finalizer.toUtf8())) catch (error:Dynamic) {
            say("extension " + id + ": " + Std.string(error));
            -9;
        }
        if (handle < 0) {
            say("extension " + id + ": load failed (" + handle + ")");
            return null;
        }
        say("extension " + id + ": the install's own DLL, " + Native.function_count(handle) + " functions");
        var ext = new NativeAne(handle, id, fingerprinted ? folder : null);
        open.set(handle, ext);
        if (!pumping) {
            pumping = true;
            Pump.add(() -> {
                drain();
                return true;
            });
        }
        return ext;
    }

    static var statusLogged = 0;
    static final WATCHED = ["SteamAir_IsOverlayEnabled", "SteamAir_ActivateGameOverlayToStore", "SteamAir_GetSteamOrder", "Init", "LoadBank"];

    static function say(text:String):Void {
        if (log != null) log(text);
    }

    static function drain():Void {
        for (_ in 0...64) {
            var from = -1;
            var length = 0;
            var bytes = Native.pop_event(from, length);
            if (bytes == null) return;
            var code = "";
            var level = "";
            var raw = bytes.toBytes(length);
            for (i in 0...length) {
                if (raw.get(i) == 0) {
                    code = raw.getString(0, i);
                    level = raw.getString(i + 1, length - i - 2);
                    break;
                }
            }
            var ext = open.get(from);
            if (statusLogged++ < 200) say("extension status event " + code + " " + level);
            if (ext != null) ext.status(code, level);
        }
    }

    override public function call(name:String, args:Array<Dynamic>):Dynamic {
        var out = new haxe.io.BytesOutput();
        for (arg in args) write(out, arg);
        var bytes = out.getBytes();
        var length = 0;
        var before = workDir == null ? null : Sys.getCwd();
        if (before != null) Sys.setCwd(workDir);
        var result = try Native.call(handle, @:privateAccess name.toUtf8(), bytes.getData().bytes, bytes.length, length)
            catch (error:Dynamic) {
                if (before != null) Sys.setCwd(before);
                throw error;
            }
        if (before != null) Sys.setCwd(before);
        if (result == null || length < 0) throw new ServiceError(3500,
            "The extension context does not have a method with the name " + name + ".");
        var input = new haxe.io.BytesInput(result.toBytes(length));
        var value = read(input);
        for (arg in args) {
            if (!Std.isOfType(arg, flash.utils.ByteArray.ByteArrayData) || input.position >= input.length) continue;
            if (input.readByte() != BYTES) break;
            var target:flash.utils.ByteArray = arg;
            var size = input.readInt32();
            var position = input.readInt32();
            target.length = size;
            for (i in 0...size) target[i] = input.readByte();
            target.position = position;
        }
        if (WATCHED.indexOf(name) >= 0 && statusLogged++ < 200) say("extension " + name + "(" + args.join(", ") + ") = " + Std.string(value));
        return value;
    }

    static function read(input:haxe.io.BytesInput):Dynamic {
        switch (input.readByte()) {
            case 0:
                var u = input.readInt32();
                return u >= 0 ? (u : Dynamic) : ((u : Float) + 4294967296.0 : Dynamic);
            case 1:
                return input.readDouble();
            case 2:
                return input.readString(input.readInt32());
            case 3:
                var kind = input.readString(input.readInt32());
                var count = input.readInt32();
                var items:Array<Dynamic> = [for (_ in 0...count) read(input)];
                if (StringTools.startsWith(kind, "Vector.<int>") || StringTools.startsWith(kind, "Vector.<uint>")) {
                    var ints:Array<Int> = [for (item in items) item == null ? 0 : Std.int(item)];
                    return Vector.ofArray(ints);
                }
                if (StringTools.startsWith(kind, "Vector")) return Vector.ofArray(items);
                return items;
            case 5:
                return input.readByte() != 0;
            case 6:
                return input.readInt32();
            case BYTES:
                var size = input.readInt32();
                var position = input.readInt32();
                var bytes = new flash.utils.ByteArray();
                for (i in 0...size) bytes.writeByte(input.readByte());
                bytes.position = position;
                return bytes;
            default:
                return null;
        }
    }

    static function write(out:haxe.io.BytesOutput, value:Dynamic):Void {
        if (value == null) {
            out.writeByte(4);
        } else if (Std.isOfType(value, String)) {
            var bytes = haxe.io.Bytes.ofString(value);
            out.writeByte(2);
            out.writeInt32(bytes.length);
            out.write(bytes);
        } else if (Std.isOfType(value, Bool)) {
            out.writeByte(0);
            out.writeInt32(value ? 1 : 0);
        } else if (Std.isOfType(value, Int)) {
            var i:Int = value;
            if (i >= 0) {
                out.writeByte(0);
                out.writeInt32(i);
            } else {
                out.writeByte(1);
                out.writeDouble(i);
            }
        } else if (Std.isOfType(value, Float)) {
            out.writeByte(1);
            out.writeDouble(value);
        } else if (Std.isOfType(value, Array)) {
            var items:Array<Dynamic> = value;
            out.writeByte(3);
            out.writeInt32(items.length);
            for (item in items) write(out, item);
        } else if (Std.isOfType(value, flash.utils.ByteArray.ByteArrayData)) {
            var bytes:flash.utils.ByteArray = value;
            out.writeByte(BYTES);
            out.writeInt32(bytes.length);
            out.writeInt32(bytes.position);
            for (i in 0...bytes.length) out.writeByte(bytes[i]);
        } else {
            out.writeByte(4);
        }
    }

    override public function dispose():Void {
        open.remove(handle);
        Native.dispose(handle);
        super.dispose();
    }
}

@:hlNative("ncane")
private extern class Native {
    static function load(dll:hl.Bytes, searchDir:hl.Bytes, initializer:hl.Bytes, finalizer:hl.Bytes):Int;
    static function function_count(handle:Int):Int;
    static function call(handle:Int, name:hl.Bytes, args:hl.Bytes, length:Int, outLength:hl.Ref<Int>):hl.Bytes;
    static function pop_event(outHandle:hl.Ref<Int>, outLength:hl.Ref<Int>):hl.Bytes;
    static function dispose(handle:Int):Void;
}
