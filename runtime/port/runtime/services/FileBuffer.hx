package port.runtime.services;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

class FileBuffer extends DataBuffer {
    public static inline var READ = "read";
    public static inline var WRITE = "write";
    public static inline var APPEND = "append";
    public static inline var UPDATE = "update";

    var path:String;
    var mode:String;
    var dirty:Bool = false;
    var open:Bool = true;
    var writeOnly:Bool;

    public function new(path:String, mode:String) {
        super();
        this.path = path;
        this.mode = mode;
        writeOnly = mode == WRITE || mode == APPEND;
        switch (mode) {
            case READ:
                load(true);
            case WRITE:
                data = Bytes.alloc(256);
                dirty = true;
            case APPEND, UPDATE:
                load(false);
                if (mode == APPEND) pos = len;
                if (!Files.exists(path)) dirty = true;
            default:
                throw new ServiceError(2008, "Parameter mode must be one of the accepted values.");
        }
    }

    function load(mustExist:Bool):Void {
        if (Files.exists(path) && !Files.isDirectory(path)) {
            var bytes = try Files.readBytes(path) catch (e:ServiceError) throw e catch (e:Dynamic) throw new ServiceError(2038, "File I/O Error.");
            data = Bytes.alloc(bytes.length > 256 ? bytes.length : 256);
            data.blit(0, bytes, 0, bytes.length);
            len = bytes.length;
        } else if (mustExist) {
            throw new ServiceError(3003, "File or directory does not exist: " + path);
        } else {
            data = Bytes.alloc(256);
        }
    }

    override function need(n:Int):Void {
        checkOpen();
        if (writeOnly) throw new ServiceError(2002, "The stream is not open for reading.");
        super.need(n);
    }

    function checkOpen():Void {
        if (!open) throw new ServiceError(2029, "The stream is closed.");
    }

    override function room(n:Int):Void {
        checkOpen();
        if (mode == READ) throw new ServiceError(2002, "The stream is not open for writing.");
        if (mode == APPEND) pos = len;
        super.room(n);
    }

    override function wrote(n:Int):Void {
        super.wrote(n);
        dirty = true;
        flush();
    }

    public function truncate():Void {
        checkOpen();
        if (pos < len) {
            len = pos;
            dirty = true;
            flush();
        }
    }

    public function flush():Void {
        if (dirty && mode != READ) {
            try Files.writeBytes(path, data.sub(0, len)) catch (e:ServiceError) throw e catch (e:Dynamic) throw new ServiceError(2038, "File I/O Error.");
            dirty = false;
        }
    }

    public function close():Void {
        if (!open) return;
        flush();
        open = false;
    }
}
