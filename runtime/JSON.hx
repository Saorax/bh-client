package;

class JSON {
   public static function parse(text:String):Dynamic {
      try {
         return haxe.Json.parse(text);
      } catch (e:Dynamic) {
         var error = new flash.errors.Error("Error #1132: Invalid JSON parse input.", 1132);
         error.name = "SyntaxError";
         throw error;
      }
   }

   public static function stringify(value:Dynamic, replacer:Dynamic = null, space:Dynamic = null):String {
      var out = new StringBuf();
      return write(out, value, "", []) ? out.toString() : null;
   }

   static function write(out:StringBuf, value:Dynamic, key:String, stack:Array<Dynamic>):Bool {
      var kind = Type.typeof(value);
      switch (kind) {
         case TObject | TClass(_):
            if (!Std.isOfType(value, String)) {
               var toJSON:Dynamic = try Reflect.field(value, "toJSON") catch (e:Dynamic) null;
               if (Reflect.isFunction(toJSON)) {
                  value = Reflect.callMethod(value, toJSON, [key]);
                  kind = Type.typeof(value);
               }
            }
         default:
      }
      switch (kind) {
         case TNull | TUnknown:
            out.add("null");
         case TBool:
            out.add(value ? "true" : "false");
         case TInt:
            out.add(Std.string(value));
         case TFloat:
            out.add(number(value));
         case TFunction:
            return false;
         case TEnum(_):
            out.add(Std.string(Type.enumIndex(value)));
         case TClass(c):
            if (c == String) quote(out, value);
            else if (Std.isOfType(value, Array)) {
               var items:Array<Dynamic> = value;
               list(out, [for (item in items) item], stack, value);
            } else if (Std.isOfType(value, port.runtime.AS3Vector)) {
               var vector:port.runtime.AS3Vector = value;
               list(out, [for (i in 0...vector.length) vector.get(i)], stack, value);
            } else if (Std.isOfType(value, flash.utils.Dictionary)) {
               var dict:flash.utils.Dictionary = value;
               var keys = [for (k in dict.keys()) k];
               object(out, [for (k in keys) Std.string(k)], [for (k in keys) dict.getValue(k)], stack, value);
            } else if (Std.isOfType(value, port.runtime.HashTable.KeyTable)) {
               var table:port.runtime.HashTable.KeyTable = value;
               var keys = table.keys();
               object(out, keys, [for (k in keys) table.getValue(k)], stack, value);
            } else if (Std.isOfType(value, haxe.ds.StringMap)) {
               var map:haxe.ds.StringMap<Dynamic> = value;
               var keys = [for (k in map.keys()) k];
               object(out, keys, [for (k in keys) map.get(k)], stack, value);
            } else {
               var names = Type.getInstanceFields(c);
               object(out, names, [for (n in names) Reflect.field(value, n)], stack, value);
            }
         case TObject:
            var names = Reflect.fields(value);
            object(out, names, [for (n in names) Reflect.field(value, n)], stack, value);
      }
      return true;
   }

   static function enter(stack:Array<Dynamic>, value:Dynamic):Void {
      for (seen in stack) {
         if (seen == value) {
            var error = new flash.errors.Error("Error #1129: Cyclic structure cannot be converted to JSON string.", 1129);
            error.name = "TypeError";
            throw error;
         }
      }
      stack.push(value);
   }

   static function list(out:StringBuf, items:Array<Dynamic>, stack:Array<Dynamic>, owner:Dynamic):Void {
      enter(stack, owner);
      out.addChar("[".code);
      for (i in 0...items.length) {
         if (i > 0) out.addChar(",".code);
         if (!write(out, items[i], Std.string(i), stack)) out.add("null");
      }
      out.addChar("]".code);
      stack.pop();
   }

   static function object(out:StringBuf, names:Array<String>, values:Array<Dynamic>, stack:Array<Dynamic>, owner:Dynamic):Void {
      enter(stack, owner);
      out.addChar("{".code);
      var first = true;
      for (i in 0...names.length) {
         var value = values[i];
         if (Reflect.isFunction(value)) continue;
         var part = new StringBuf();
         if (!write(part, value, names[i], stack)) continue;
         if (!first) out.addChar(",".code);
         first = false;
         quote(out, names[i]);
         out.addChar(":".code);
         out.add(part.toString());
      }
      out.addChar("}".code);
      stack.pop();
   }

   static function quote(out:StringBuf, s:String):Void {
      out.addChar("\"".code);
      var start = 0;
      for (i in 0...s.length) {
         var c = StringTools.fastCodeAt(s, i);
         var escaped:String = switch (c) {
            case '"'.code: "\\\"";
            case "\\".code: "\\\\";
            case 8: "\\b";
            case 9: "\\t";
            case 10: "\\n";
            case 12: "\\f";
            case 13: "\\r";
            default: c < 32 ? "\\u" + StringTools.hex(c, 4).toLowerCase() : null;
         }
         if (escaped != null) {
            if (i > start) out.addSub(s, start, i - start);
            out.add(escaped);
            start = i + 1;
         }
      }
      if (start < s.length) out.addSub(s, start, s.length - start);
      out.addChar("\"".code);
   }

   public static function number(f:Float):String {
      if (Math.isNaN(f) || !Math.isFinite(f)) return "null";
      if (f == 0) return "0";
      var negative = f < 0;
      var v = negative ? -f : f;
      var short = Std.string(v);
      var found = v < 2.2250738585072014e-308 ? shortest(v, 1) : Std.parseFloat(short) == v ? parsed(short) : shortest(v, 16);
      var s = found.digits;
      var n = found.point;
      var end = s.length;
      while (end > 1 && StringTools.fastCodeAt(s, end - 1) == "0".code) end--;
      s = s.substr(0, end);
      var k = s.length;
      var text = if (k <= n && n <= 21) s + StringTools.rpad("", "0", n - k);
         else if (0 < n && n <= 21) s.substr(0, n) + "." + s.substr(n);
         else if (-6 < n && n <= 0) "0." + StringTools.rpad("", "0", -n) + s;
         else s.charAt(0) + (k > 1 ? "." + s.substr(1) : "") + "e" + (n - 1 >= 0 ? "+" : "-") + Std.string(n - 1 >= 0 ? n - 1 : 1 - n);
      return negative ? "-" + text : text;
   }

   static function parsed(text:String):{digits:String, point:Int} {
      var e = text.indexOf("e");
      var mantissa = e < 0 ? text : text.substr(0, e);
      var exponent = e < 0 ? 0 : Std.parseInt(StringTools.replace(text.substr(e + 1), "+", ""));
      var dot = mantissa.indexOf(".");
      var all = dot < 0 ? mantissa : mantissa.substr(0, dot) + mantissa.substr(dot + 1);
      var point = (dot < 0 ? mantissa.length : dot) + exponent;
      var start = 0;
      while (start < all.length - 1 && StringTools.fastCodeAt(all, start) == "0".code) start++;
      return {digits: all.substr(start), point: point - start};
   }

   static function shortest(v:Float, from:Int):{digits:String, point:Int} {
      var exact = digits(v);
      for (p in from...18) {
         var rounded = round(exact.digits, exact.point, p);
         if (Std.parseFloat("0." + rounded.digits + "e" + rounded.point) == v) return rounded;
      }
      return exact;
   }

   static function round(all:String, point:Int, p:Int):{digits:String, point:Int} {
      if (all.length <= p) return {digits: all, point: point};
      var head = [for (i in 0...p) StringTools.fastCodeAt(all, i) - "0".code];
      var next = StringTools.fastCodeAt(all, p) - "0".code;
      var up = next > 5;
      if (next == 5) {
         var rest = false;
         for (i in p + 1...all.length) if (StringTools.fastCodeAt(all, i) != "0".code) { rest = true; break; }
         up = rest || head[p - 1] % 2 == 1;
      }
      if (up) {
         var i = p - 1;
         while (i >= 0) {
            if (head[i] < 9) { head[i]++; break; }
            head[i] = 0;
            i--;
         }
         if (i < 0) {
            head.unshift(1);
            head.pop();
            point++;
         }
      }
      return {digits: [for (d in head) String.fromCharCode("0".code + d)].join(""), point: point};
   }

   static inline var BASE = 10000000.0;

   static function digits(v:Float):{digits:String, point:Int} {
      var bits = haxe.io.FPHelper.doubleToI64(v);
      var high = bits.high;
      var low:Float = bits.low < 0 ? bits.low + 4294967296.0 : bits.low;
      var biased = (high >>> 20) & 0x7FF;
      var top = high & 0xFFFFF;
      if (biased != 0) top |= 0x100000;
      var e2 = (biased == 0 ? 1 : biased) - 1075;
      var m:Float = top * 4294967296.0 + low;
      var limbs:Array<Float> = [];
      while (m > 0) {
         var limb = m % BASE;
         limbs.push(limb);
         m = (m - limb) / BASE;
      }
      if (e2 >= 0) {
         var left = e2;
         while (left > 0) {
            var step = left > 20 ? 20 : left;
            multiply(limbs, Math.pow(2, step));
            left -= step;
         }
      } else {
         var left = -e2;
         while (left > 0) {
            var step = left > 9 ? 9 : left;
            multiply(limbs, Math.pow(5, step));
            left -= step;
         }
      }
      var text = new StringBuf();
      var i = limbs.length - 1;
      text.add(Std.string(Std.int(limbs[i])));
      while (--i >= 0) text.add(StringTools.lpad(Std.string(Std.int(limbs[i])), "0", 7));
      var all = text.toString();
      return {digits: all, point: all.length + (e2 < 0 ? e2 : 0)};
   }

   static function multiply(limbs:Array<Float>, factor:Float):Void {
      var carry = 0.0;
      for (i in 0...limbs.length) {
         var product = limbs[i] * factor + carry;
         var limb = product % BASE;
         limbs[i] = limb;
         carry = (product - limb) / BASE;
      }
      while (carry > 0) {
         var limb = carry % BASE;
         limbs.push(limb);
         carry = (carry - limb) / BASE;
      }
   }
}
