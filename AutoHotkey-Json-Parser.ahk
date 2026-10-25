#Requires AutoHotkey v2.0

/**
 * JSON.ahk  -  a complete JSON library for AutoHotkey v2 (written from scratch)
 *
 * PARSE
 *   JSON.Parse(text, opts?)            text -> Map / Array / String / Number / ...
 *   JSON.TryParse(text, &result, opts?) bool, error stored in JSON.LastError
 *   JSON.IsValid(text, opts?)          bool
 *   JSON.Load(file, opts?)             parse a file (UTF-8)
 *
 * CREATE
 *   JSON.Stringify(value, indent?, opts?)   value -> JSON text (indent: number of spaces or string)
 *   JSON.Save(value, file, indent?, opts?)  write to a file (UTF-8, no BOM)
 *   JSON.Prettify(text) / JSON.Minify(text) reformat text (comments and trailing commas are dropped)
 *   JSON.Null, JSON.Bool(true/false)        literals that survive round trips
 *
 * MANAGE  (paths:  "a.b[1].c"   "$.a.b[-1]"   ["a", 1, "c"]   ["key.with.dot"])
 *   JSON.Get(obj, path, default?)  JSON.Set(obj, path, value)  JSON.Has(obj, path)
 *   JSON.Delete(obj, path)         JSON.Query(obj, "items[*].name")   (wildcards)
 *   JSON.Merge(target, source)     JSON.DeepClone(v)     JSON.Equals(a, b)
 *   JSON.Keys / Values / Count     JSON.Flatten / Unflatten     JSON.Walk(obj, fn)
 *
 * NOTES
 *   - Array indexes in paths are 1-based (AHK style); negative indexes count from the end.
 *   - true / false / null parse to 1 / 0 / "" by default. Use {Preserve: true} to keep
 *     them as JSON.Bool(true) / JSON.Bool(false) / JSON.Null (needed for exact round trips).
 *   - AHK Maps enumerate in sorted key order, so object key order is not preserved.
 *   - Options (global defaults in JSON.Options, or per call as an object / Map):
 *       Parse:     AsMap, Preserve, Comments, TrailingCommas, Strict, MaxDepth, Reviver
 *       Stringify: EscapeUnicode, EscapeSlash, Replacer
 */
class JSON {
    static Options := {
        AsMap: true,            ; objects -> Map (false -> plain Object)
        Preserve: false,        ; keep true/false/null as JSON.Bool / JSON.Null
        Comments: false,        ; allow // and /* */ comments (JSONC)
        TrailingCommas: false,  ; allow [1,2,] and {"a":1,}
        Strict: false,          ; reject raw control characters inside strings
        MaxDepth: 512,          ; nesting limit
        Reviver: "",            ; fn(key, value) -> value, called bottom-up
        EscapeUnicode: false,   ; write non-ASCII as \uXXXX
        EscapeSlash: false,     ; write / as \/
        Replacer: ""            ; fn(key, value) -> value, called before writing
    }
    static LastError := ""
    static _ln := ""
    static _lt := ""
    static _lf := ""

    ; =====================================================================
    ;  Literals
    ; =====================================================================
    class Literal {
        __New(name, native) {
            this.Name := name
            this.Native := native
        }
        ToString() => this.Name
    }

    static Null {
        get {
            if !JSON._ln
                JSON._ln := JSON.Literal("null", "")
            return JSON._ln
        }
    }

    static Bool(v) {
        if v {
            if !JSON._lt
                JSON._lt := JSON.Literal("true", 1)
            return JSON._lt
        }
        if !JSON._lf
            JSON._lf := JSON.Literal("false", 0)
        return JSON._lf
    }

    static IsNull(v) => (v is JSON.Literal) && v.Name == "null"

    ; Convert a JSON.Literal into the native AHK value (1 / 0 / "")
    static ToNative(v) => (v is JSON.Literal) ? v.Native : v

    ; "object" | "array" | "string" | "number" | "boolean" | "null"
    static TypeOf(v) {
        if v is JSON.Literal
            return v.Name == "null" ? "null" : "boolean"
        if v is Array
            return "array"
        if IsObject(v)
            return "object"
        return (v is String) ? "string" : "number"
    }

    ; =====================================================================
    ;  Errors
    ; =====================================================================
    class ParseError extends Error {
        __New(msg, text := "", pos := 1) {
            before := SubStr(text, 1, pos - 1)
            StrReplace(before, "`n", , , &nl)
            lastNL := InStr(before, "`n", true, -1)
            this.TextPos := pos
            this.TextLine := nl + 1
            this.TextColumn := pos - lastNL
            near := RegExReplace(SubStr(text, Max(pos - 15, 1), 30), "\R", " ")
            super.__New(Format("{} at line {}, column {} (near: `"{}`")", msg, this.TextLine, this.TextColumn, near))
        }
    }

    ; =====================================================================
    ;  Public: parsing
    ; =====================================================================
    static Parse(text, opts := "") {
        if IsObject(text)
            throw TypeError("JSON.Parse expects a string")
        value := JSON._Parser(String(text), opts).Run()
        reviver := JSON._O(opts, "Reviver")
        if IsObject(reviver)
            value := JSON._Revive("", value, reviver)
        return value
    }

    static Decode(text, opts := "") => JSON.Parse(text, opts)

    static TryParse(text, &result, opts := "") {
        try {
            result := JSON.Parse(text, opts)
            JSON.LastError := ""
            return true
        } catch Error as e {
            result := ""
            JSON.LastError := e
            return false
        }
    }

    static IsValid(text, opts := "") => JSON.TryParse(text, &_, opts)

    static Load(path, opts := "", encoding := "UTF-8") => JSON.Parse(FileRead(path, encoding), opts)

    ; =====================================================================
    ;  Public: writing
    ; =====================================================================
    static Stringify(value, indent := "", opts := "") => JSON._Writer(indent, opts).Run(value)

    static Encode(value, indent := "", opts := "") => JSON.Stringify(value, indent, opts)

    static Save(value, path, indent := 2, opts := "", encoding := "UTF-8-RAW") {
        text := JSON.Stringify(value, indent, opts)
        f := FileOpen(path, "w", encoding)
        f.Write(text)
        f.Close()
    }

    static Prettify(text, indent := 2) => JSON.Stringify(JSON._Lenient(text), indent)

    static Minify(text) => JSON.Stringify(JSON._Lenient(text), "")

    ; Quote and escape a single string as a JSON string literal
    static Quote(str, opts := "") => JSON._Writer("", opts).Quote(String(str))

    static _Lenient(text) => JSON.Parse(text, {Preserve: true, Comments: true, TrailingCommas: true})

    ; =====================================================================
    ;  Public: managing data
    ; =====================================================================
    static Has(obj, path) => JSON._Resolve(obj, JSON._Keys(path), &_)

    static Get(obj, path, defVal?) {
        if JSON._Resolve(obj, JSON._Keys(path), &found)
            return found
        if IsSet(defVal)
            return defVal
        throw ValueError("Path not found: " . (path is Array ? JSON._PathStr(path) : path))
    }

    static Set(obj, path, value) {
        keys := JSON._Keys(path)
        if keys.Length = 0
            throw ValueError("Empty path")
        if !IsObject(obj) || (obj is JSON.Literal)
            throw TypeError("JSON.Set needs a Map, Array or Object as the root")
        cur := obj
        last := keys.Length
        for i, k in keys {
            if i = last {
                JSON._Put(cur, k, value)
                break
            }
            if !(JSON._Child(cur, k, &nxt) && IsObject(nxt) && !(nxt is JSON.Literal)) {
                if keys[i + 1] is Integer
                    nxt := []
                else
                    nxt := JSON.Options.AsMap ? Map() : {}
                JSON._Put(cur, k, nxt)
            }
            cur := nxt
        }
        return obj
    }

    ; Returns true if something was deleted
    static Delete(obj, path) {
        keys := JSON._Keys(path).Clone()
        if keys.Length = 0
            throw ValueError("Empty path")
        k := keys.Pop()
        if !JSON._Resolve(obj, keys, &parent)
            return false
        if parent is Map {
            kk := parent.Has(k) ? k : String(k)
            if !parent.Has(kk)
                return false
            parent.Delete(kk)
            return true
        }
        if parent is Array {
            if !IsInteger(k)
                return false
            idx := Integer(k)
            if idx < 0
                idx := parent.Length + 1 + idx
            if idx < 1 || idx > parent.Length
                return false
            parent.RemoveAt(idx)
            return true
        }
        if IsObject(parent) && !(parent is JSON.Literal) && HasProp(parent, String(k)) {
            parent.DeleteProp(String(k))
            return true
        }
        return false
    }

    ; All matches of a path that may contain * wildcards, e.g. "users[*].name"
    static Query(obj, path) {
        results := []
        JSON._Q(obj, JSON._Keys(path), 1, results)
        return results
    }

    static Keys(obj) {
        result := []
        if obj is Map {
            for k in obj {
                result.Push(k)
            }
        } else if obj is Array {
            loop obj.Length {
                result.Push(A_Index)
            }
        } else if JSON._IsPlain(obj) {
            for k in obj.OwnProps() {
                result.Push(k)
            }
        } else {
            throw TypeError("Expected a Map, Array or Object")
        }
        return result
    }

    static Values(obj) {
        result := []
        if obj is Map {
            for k, v in obj {
                result.Push(v)
            }
        } else if obj is Array {
            loop obj.Length {
                if obj.Has(A_Index)
                    result.Push(obj[A_Index])
            }
        } else if JSON._IsPlain(obj) {
            for k, v in obj.OwnProps() {
                result.Push(v)
            }
        } else {
            throw TypeError("Expected a Map, Array or Object")
        }
        return result
    }

    static Count(obj) {
        if obj is Map
            return obj.Count
        if obj is Array
            return obj.Length
        n := 0
        if JSON._IsPlain(obj) {
            for k in obj.OwnProps() {
                n += 1
            }
            return n
        }
        throw TypeError("Expected a Map, Array or Object")
    }

    ; Recursive copy. Literals are shared (they are immutable singletons).
    static DeepClone(v) {
        if !IsObject(v) || (v is JSON.Literal) || (v is Func)
            return v
        if v is Map {
            m := Map()
            m.CaseSense := v.CaseSense
            for k, x in v {
                m[k] := JSON.DeepClone(x)
            }
            return m
        }
        if v is Array {
            a := []
            a.Length := v.Length
            loop v.Length {
                if v.Has(A_Index)
                    a[A_Index] := JSON.DeepClone(v[A_Index])
            }
            return a
        }
        o := {}
        ObjSetBase(o, ObjGetBase(v))
        for k, x in v.OwnProps() {
            o.DefineProp(k, {Value: JSON.DeepClone(x)})
        }
        return o
    }

    ; Merge source into target (modifies and returns target).
    ; Objects are merged recursively when deep = true; arrays are appended at the top level
    ; and replaced when nested.
    static Merge(target, source, deep := true) {
        if (target is Array) && (source is Array) {
            loop source.Length {
                if source.Has(A_Index)
                    target.Push(JSON.DeepClone(source[A_Index]))
            }
            return target
        }
        if (target is Map) && (source is Map) {
            for k, v in source {
                if deep && target.Has(k) && JSON._Mergeable(target[k], v)
                    JSON.Merge(target[k], v, true)
                else
                    target[k] := JSON.DeepClone(v)
            }
            return target
        }
        if JSON._IsPlain(target) && JSON._IsPlain(source) {
            for k, v in source.OwnProps() {
                if deep && target.HasOwnProp(k) && JSON._Mergeable(target.%k%, v)
                    JSON.Merge(target.%k%, v, true)
                else
                    target.%k% := JSON.DeepClone(v)
            }
            return target
        }
        throw TypeError("Merge needs two Maps, two Objects or two Arrays")
    }

    ; Deep structural equality. Numbers compare numerically, strings case-sensitively.
    static Equals(a, b) {
        if a is JSON.Literal
            a := a.Native
        if b is JSON.Literal
            b := b.Native
        ao := IsObject(a)
        bo := IsObject(b)
        if ao != bo
            return false
        if !ao {
            sa := a is String
            sb := b is String
            if sa != sb
                return false
            return sa ? (a == b) : (a = b)
        }
        if a is Map {
            if !(b is Map) || a.Count != b.Count
                return false
            for k, v in a {
                if !b.Has(k) || !JSON.Equals(v, b[k])
                    return false
            }
            return true
        }
        if a is Array {
            if !(b is Array) || a.Length != b.Length
                return false
            loop a.Length {
                ha := a.Has(A_Index)
                if ha != b.Has(A_Index)
                    return false
                if ha && !JSON.Equals(a[A_Index], b[A_Index])
                    return false
            }
            return true
        }
        if !JSON._IsPlain(a) || !JSON._IsPlain(b)
            return ObjPtr(a) = ObjPtr(b)
        if JSON.Count(a) != JSON.Count(b)
            return false
        for k, v in a.OwnProps() {
            if !b.HasOwnProp(k) || !JSON.Equals(v, b.%k%)
                return false
        }
        return true
    }

    ; Nested structure -> Map of  path => leaf  (paths use the same syntax as Get/Set)
    static Flatten(obj) {
        out := Map()
        JSON._Flat(obj, "", out)
        return out
    }

    static Unflatten(flat) {
        root := 0
        for path, v in flat {
            if !IsObject(root)
                root := (SubStr(path, 1, 1) = "[") ? [] : (JSON.Options.AsMap ? Map() : {})
            JSON.Set(root, path, JSON.DeepClone(v))
        }
        return IsObject(root) ? root : Map()
    }

    ; Visit every node depth-first. fn(path, value, parent, key); return true to stop.
    static Walk(obj, fn) => JSON._WalkRec(obj, "", "", "", fn)

    ; =====================================================================
    ;  Internals: shared helpers
    ; =====================================================================
    static _O(opts, name) {
        if IsObject(opts) {
            if opts is Map {
                if opts.Has(name)
                    return opts[name]
            } else if HasProp(opts, name) {
                return opts.%name%
            }
        }
        return JSON.Options.%name%
    }

    static _Rep(s, n) {
        out := ""
        loop n {
            out .= s
        }
        return out
    }

    static _IsPlain(v) => IsObject(v) && !(v is Map) && !(v is Array) && !(v is Func) && !(v is JSON.Literal)

    static _Mergeable(a, b) => ((a is Map) && (b is Map)) || (JSON._IsPlain(a) && JSON._IsPlain(b))

    static _Revive(key, val, fn) {
        if val is Array {
            loop val.Length {
                if val.Has(A_Index)
                    val[A_Index] := JSON._Revive(A_Index, val[A_Index], fn)
            }
        } else if val is Map {
            keys := []
            for k in val {
                keys.Push(k)
            }
            for k in keys {
                val[k] := JSON._Revive(k, val[k], fn)
            }
        } else if JSON._IsPlain(val) {
            names := []
            for n in val.OwnProps() {
                names.Push(n)
            }
            for n in names {
                val.%n% := JSON._Revive(n, val.%n%, fn)
            }
        }
        return fn(key, val)
    }

    ; ---------------------------------------------------------------------
    ;  Path handling
    ; ---------------------------------------------------------------------
    static _Keys(path) {
        if path is Array
            return path
        if IsObject(path)
            throw TypeError("A path must be a string, an integer or an Array")
        if IsInteger(path)
            return [Integer(path)]
        p := Trim(String(path))
        keys := []
        n := StrLen(p)
        i := (SubStr(p, 1, 1) = "$") ? 2 : 1
        while i <= n {
            c := SubStr(p, i, 1)
            if c = "." {
                i += 1
                continue
            }
            if c = "[" {
                if RegExMatch(p, "A)\[\s*(-?\d+)\s*\]", &m, i) {
                    keys.Push(Integer(m[1]))
                } else if RegExMatch(p, "A)\[\s*\*\s*\]", &m, i) {
                    keys.Push("*")
                } else if RegExMatch(p, 'A)\[\s*"((?:[^"\\]|\\.)*)"\s*\]', &m, i) {
                    keys.Push(RegExReplace(m[1], "\\(.)", "$1"))
                } else if RegExMatch(p, "A)\[\s*'((?:[^'\\]|\\.)*)'\s*\]", &m, i) {
                    keys.Push(RegExReplace(m[1], "\\(.)", "$1"))
                } else {
                    throw ValueError("Invalid path syntax at position " . i . ": " . p)
                }
                i += m.Len[0]
                continue
            }
            if !RegExMatch(p, "A)[^.\[]+", &m, i)
                throw ValueError("Invalid path syntax at position " . i . ": " . p)
            keys.Push(m[0])
            i += m.Len[0]
        }
        return keys
    }

    static _Append(path, k) {
        if (k is Integer)
            return path . "[" . k . "]"
        k := String(k)
        if k = "" || IsInteger(k) || RegExMatch(k, '[.\[\]"*$]') {
            esc := StrReplace(StrReplace(k, "\", "\\"), '"', '\"')
            return path . '["' . esc . '"]'
        }
        return (path = "") ? k : path . "." . k
    }

    static _PathStr(keys) {
        s := ""
        for k in keys {
            s := JSON._Append(s, k)
        }
        return s
    }

    static _Child(c, k, &out) {
        if c is Map {
            if c.Has(k) {
                out := c[k]
                return true
            }
            sk := String(k)
            if c.Has(sk) {
                out := c[sk]
                return true
            }
            return false
        }
        if c is Array {
            if !IsInteger(k)
                return false
            idx := Integer(k)
            if idx < 0
                idx := c.Length + 1 + idx
            if idx >= 1 && idx <= c.Length && c.Has(idx) {
                out := c[idx]
                return true
            }
            return false
        }
        if IsObject(c) && !(c is JSON.Literal) && !(c is Func) {
            sk := String(k)
            if sk != "" && HasProp(c, sk) {
                out := c.%sk%
                return true
            }
        }
        return false
    }

    static _Resolve(obj, keys, &out) {
        out := obj
        for k in keys {
            if !JSON._Child(out, k, &nxt)
                return false
            out := nxt
        }
        return true
    }

    static _Put(c, k, v) {
        if c is Map {
            c[c.Has(k) ? k : String(k)] := v
            return
        }
        if c is Array {
            if !IsInteger(k)
                throw TypeError("Array index must be an integer, got: " . k)
            idx := Integer(k)
            if idx < 0
                idx := c.Length + 1 + idx
            if idx < 1
                throw IndexError("Array index out of range: " . k)
            if idx > c.Length
                c.Length := idx
            c[idx] := v
            return
        }
        if IsObject(c) && !(c is JSON.Literal) && !(c is Func) {
            c.DefineProp(String(k), {Value: v})
            return
        }
        throw TypeError("Cannot set a child on a non-container value")
    }

    static _Q(cur, keys, i, results) {
        if i > keys.Length {
            results.Push(cur)
            return
        }
        k := keys[i]
        if (k is String) && k == "*" {
            if cur is Map {
                for key, v in cur {
                    JSON._Q(v, keys, i + 1, results)
                }
            } else if cur is Array {
                loop cur.Length {
                    if cur.Has(A_Index)
                        JSON._Q(cur[A_Index], keys, i + 1, results)
                }
            } else if JSON._IsPlain(cur) {
                for key, v in cur.OwnProps() {
                    JSON._Q(v, keys, i + 1, results)
                }
            }
            return
        }
        if JSON._Child(cur, k, &nxt)
            JSON._Q(nxt, keys, i + 1, results)
    }

    static _Flat(v, path, out) {
        if v is Map {
            if v.Count = 0 && path != "" {
                out[path] := v
                return
            }
            for k, x in v {
                JSON._Flat(x, JSON._Append(path, String(k)), out)
            }
        } else if v is Array {
            if v.Length = 0 && path != "" {
                out[path] := v
                return
            }
            loop v.Length {
                if v.Has(A_Index)
                    JSON._Flat(v[A_Index], JSON._Append(path, A_Index), out)
            }
        } else if JSON._IsPlain(v) {
            for k, x in v.OwnProps() {
                JSON._Flat(x, JSON._Append(path, k), out)
            }
        } else {
            out[path] := v
        }
    }

    static _WalkRec(v, path, parent, key, fn) {
        if fn(path, v, parent, key)
            return true
        if v is Map {
            for k, x in v {
                if JSON._WalkRec(x, JSON._Append(path, String(k)), v, k, fn)
                    return true
            }
        } else if v is Array {
            loop v.Length {
                if v.Has(A_Index) {
                    if JSON._WalkRec(v[A_Index], JSON._Append(path, A_Index), v, A_Index, fn)
                        return true
                }
            }
        } else if JSON._IsPlain(v) {
            for k, x in v.OwnProps() {
                if JSON._WalkRec(x, JSON._Append(path, k), v, k, fn)
                    return true
            }
        }
        return false
    }

    ; =====================================================================
    ;  Parser
    ; =====================================================================
    class _Parser {
        __New(text, opts) {
            this.t := text
            this.p := 1
            this.n := StrLen(text)
            this.depth := 0
            this.asMap := JSON._O(opts, "AsMap")
            this.keep := JSON._O(opts, "Preserve")
            this.cm := JSON._O(opts, "Comments")
            this.tc := JSON._O(opts, "TrailingCommas")
            this.strict := JSON._O(opts, "Strict")
            this.maxDepth := JSON._O(opts, "MaxDepth")
        }

        Run() {
            if this.n >= 1 && SubStr(this.t, 1, 1) = Chr(0xFEFF)
                this.p := 2
            this.Ws()
            value := this.Val()
            this.Ws()
            if this.p <= this.n
                this.Fail("Unexpected trailing characters")
            return value
        }

        Fail(msg, pos := 0) {
            throw JSON.ParseError(msg, this.t, pos ? pos : this.p)
        }

        Enter() {
            this.depth += 1
            if this.depth > this.maxDepth
                this.Fail("Maximum nesting depth (" . this.maxDepth . ") exceeded")
        }

        Ws() {
            loop {
                if RegExMatch(this.t, "A)[ \t\r\n]+", &m, this.p)
                    this.p += m.Len[0]
                if !this.cm
                    break
                two := SubStr(this.t, this.p, 2)
                if two = "//" {
                    e := InStr(this.t, "`n", true, this.p)
                    this.p := e ? e + 1 : this.n + 1
                } else if two = "/*" {
                    e := InStr(this.t, "*/", true, this.p + 2)
                    if !e
                        this.Fail("Unterminated comment")
                    this.p := e + 2
                } else {
                    break
                }
            }
        }

        Val() {
            c := SubStr(this.t, this.p, 1)
            switch c, true {
                case "{":
                    return this.Obj()
                case "[":
                    return this.Arr()
                case '"':
                    return this.Str()
                case "t":
                    return this.Lit("true", this.keep ? JSON.Bool(true) : true)
                case "f":
                    return this.Lit("false", this.keep ? JSON.Bool(false) : false)
                case "n":
                    return this.Lit("null", this.keep ? JSON.Null : "")
                case "":
                    this.Fail("Unexpected end of input")
                default:
                    if c = "-" || IsDigit(c)
                        return this.Num()
                    this.Fail("Unexpected character '" . c . "'")
            }
        }

        Lit(word, value) {
            len := StrLen(word)
            if SubStr(this.t, this.p, len) == word {
                this.p += len
                return value
            }
            this.Fail("Invalid literal, expected '" . word . "'")
        }

        Num() {
            if !RegExMatch(this.t, "A)-?(?:0|[1-9]\d*)(?<f>\.\d+)?(?<e>[eE][+-]?\d+)?", &m, this.p)
                this.Fail("Invalid number")
            s := m[0]
            this.p += m.Len[0]
            if m["f"] = "" && m["e"] = "" {
                ; Integers with 19+ characters could overflow Int64, so use Float for those
                return StrLen(s) > 18 ? Float(s) : Integer(s)
            }
            if m["f"] = ""
                s := RegExReplace(s, "i)e", ".0e", , 1)
            return Float(s)
        }

        Str() {
            start := this.p + 1
            q := start
            loop {
                q := InStr(this.t, '"', true, q)
                if !q
                    this.Fail("Unterminated string", this.p)
                k := q - 1
                bs := 0
                while k >= start && SubStr(this.t, k, 1) = "\" {
                    bs += 1
                    k -= 1
                }
                if Mod(bs, 2) = 0
                    break
                q += 1
            }
            raw := SubStr(this.t, start, q - start)
            this.p := q + 1
            if this.strict && RegExMatch(raw, "[\x00-\x1F]", &cc)
                this.Fail("Unescaped control character in string", start + cc.Pos - 1)
            if !InStr(raw, "\")
                return raw
            return this.Unesc(raw, start)
        }

        Unesc(raw, base) {
            out := ""
            i := 1
            while (j := InStr(raw, "\", true, i)) {
                out .= SubStr(raw, i, j - i)
                c := SubStr(raw, j + 1, 1)
                i := j + 2
                switch c, true {
                    case '"':
                        out .= '"'
                    case "\":
                        out .= "\"
                    case "/":
                        out .= "/"
                    case "b":
                        out .= Chr(8)
                    case "f":
                        out .= Chr(12)
                    case "n":
                        out .= "`n"
                    case "r":
                        out .= "`r"
                    case "t":
                        out .= "`t"
                    case "u":
                        hex := SubStr(raw, j + 2, 4)
                        if !RegExMatch(hex, "^[0-9A-Fa-f]{4}$")
                            this.Fail("Invalid \u escape sequence", base + j - 1)
                        out .= Chr("0x" . hex)
                        i := j + 6
                    default:
                        this.Fail("Invalid escape sequence '\" . c . "'", base + j - 1)
                }
            }
            return out . SubStr(raw, i)
        }

        Arr() {
            this.Enter()
            arr := []
            this.p += 1
            this.Ws()
            if SubStr(this.t, this.p, 1) = "]" {
                this.p += 1
                this.depth -= 1
                return arr
            }
            loop {
                this.Ws()
                arr.Push(this.Val())
                this.Ws()
                c := SubStr(this.t, this.p, 1)
                if c = "," {
                    this.p += 1
                    if this.tc {
                        this.Ws()
                        if SubStr(this.t, this.p, 1) = "]" {
                            this.p += 1
                            break
                        }
                    }
                    continue
                }
                if c = "]" {
                    this.p += 1
                    break
                }
                this.Fail(c = "" ? "Unterminated array" : "Expected ',' or ']'")
            }
            this.depth -= 1
            return arr
        }

        Obj() {
            this.Enter()
            obj := this.asMap ? Map() : {}
            this.p += 1
            this.Ws()
            if SubStr(this.t, this.p, 1) = "}" {
                this.p += 1
                this.depth -= 1
                return obj
            }
            loop {
                this.Ws()
                if SubStr(this.t, this.p, 1) != '"'
                    this.Fail(this.p > this.n ? "Unterminated object" : "Expected a string key")
                keyPos := this.p
                key := this.Str()
                this.Ws()
                if SubStr(this.t, this.p, 1) != ":"
                    this.Fail("Expected ':' after object key")
                this.p += 1
                this.Ws()
                val := this.Val()
                if this.asMap {
                    obj[key] := val
                } else {
                    if key = ""
                        this.Fail("Empty keys are not supported when AsMap is false", keyPos)
                    obj.DefineProp(key, {Value: val})
                }
                this.Ws()
                c := SubStr(this.t, this.p, 1)
                if c = "," {
                    this.p += 1
                    if this.tc {
                        this.Ws()
                        if SubStr(this.t, this.p, 1) = "}" {
                            this.p += 1
                            break
                        }
                    }
                    continue
                }
                if c = "}" {
                    this.p += 1
                    break
                }
                this.Fail(c = "" ? "Unterminated object" : "Expected ',' or '}'")
            }
            this.depth -= 1
            return obj
        }
    }

    ; =====================================================================
    ;  Writer
    ; =====================================================================
    class _Writer {
        __New(indent, opts) {
            if IsInteger(indent)
                this.unit := JSON._Rep(" ", Min(Max(Integer(indent), 0), 32))
            else
                this.unit := String(indent)
            this.pretty := this.unit != ""
            this.esc := JSON._O(opts, "EscapeUnicode")
            this.escSlash := JSON._O(opts, "EscapeSlash")
            r := JSON._O(opts, "Replacer")
            this.rep := IsObject(r) ? r : ""
            this.seen := Map()
            this.pads := Map()
        }

        Run(value) => this.Ser(value, "", 0)

        Ser(v, key, lvl) {
            if IsObject(this.rep)
                v := this.rep.Call(key, v)
            return this.Val(v, key, lvl)
        }

        Val(v, key, lvl) {
            if !IsObject(v)
                return this.Scalar(v)
            if v is JSON.Literal
                return v.Name
            if v is Func
                throw TypeError("Functions cannot be converted to JSON")
            if HasMethod(v, "ToJSON") {
                r := v.ToJSON()
                if IsObject(r) && ObjPtr(r) = ObjPtr(v)
                    throw Error("ToJSON() must not return the same object")
                return this.Val(r, key, lvl)
            }
            id := ObjPtr(v)
            if this.seen.Has(id)
                throw Error("Circular reference detected while converting to JSON")
            this.seen[id] := true
            try
                result := this.Cont(v, lvl)
            finally
                this.seen.Delete(id)
            return result
        }

        Scalar(v) {
            switch Type(v) {
                case "String":
                    return this.Quote(v)
                case "Integer":
                    return String(v)
                case "Float":
                    if v != v || Abs(v) > 1.7976931348623157e308
                        return "null"
                    return String(v)
                default:
                    throw TypeError("Cannot convert a value of type " . Type(v) . " to JSON")
            }
        }

        Cont(v, lvl) {
            items := []
            sep := this.pretty ? ": " : ":"
            if v is Map {
                for k, x in v {
                    ks := String(k)
                    items.Push(this.Quote(ks) . sep . this.Ser(x, ks, lvl + 1))
                }
                return this.Wrap("{", "}", items, lvl)
            }
            if v is Array {
                loop v.Length {
                    i := A_Index
                    items.Push(this.Ser(v.Has(i) ? v[i] : JSON.Null, i, lvl + 1))
                }
                return this.Wrap("[", "]", items, lvl)
            }
            for k, x in v.OwnProps() {
                if x is Func
                    continue
                items.Push(this.Quote(String(k)) . sep . this.Ser(x, k, lvl + 1))
            }
            return this.Wrap("{", "}", items, lvl)
        }

        Wrap(open, close, items, lvl) {
            if items.Length = 0
                return open . close
            body := ""
            if !this.pretty {
                for it in items {
                    body .= (A_Index > 1 ? "," : "") . it
                }
                return open . body . close
            }
            pad := this.Pad(lvl + 1)
            last := items.Length
            for it in items {
                body .= pad . it . (A_Index < last ? "," : "") . "`n"
            }
            return open . "`n" . body . this.Pad(lvl) . close
        }

        Pad(lvl) {
            if !this.pads.Has(lvl)
                this.pads[lvl] := JSON._Rep(this.unit, lvl)
            return this.pads[lvl]
        }

        Quote(s) {
            if RegExMatch(s, '[\\"\x00-\x1F]') {
                s := StrReplace(s, "\", "\\")
                s := StrReplace(s, '"', '\"')
                s := StrReplace(s, "`n", "\n")
                s := StrReplace(s, "`r", "\r")
                s := StrReplace(s, "`t", "\t")
                s := StrReplace(s, Chr(8), "\b")
                s := StrReplace(s, Chr(12), "\f")
                if RegExMatch(s, "[\x00-\x1F]")
                    s := this.EscRe(s, "[\x00-\x1F]")
            }
            if this.esc && RegExMatch(s, "[^\x00-\x7F]")
                s := this.EscRe(s, "[^\x00-\x7F]")
            if this.escSlash
                s := StrReplace(s, "/", "\/")
            return '"' . s . '"'
        }

        ; Replace every match of pat by \uXXXX (surrogate pairs for characters above U+FFFF)
        EscRe(s, pat) {
            pos := 1
            while (pos := RegExMatch(s, pat, &m, pos)) {
                cp := Ord(m[0])
                len := StrLen(m[0])
                if cp > 0xFFFF {
                    cp -= 0x10000
                    rep := Format("\u{:04X}\u{:04X}", 0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF))
                } else {
                    rep := Format("\u{:04X}", cp)
                }
                s := SubStr(s, 1, pos - 1) . rep . SubStr(s, pos + len)
                pos += StrLen(rep)
            }
            return s
        }
    }
}

; =========================================================================
;  Demo: runs only when this file is executed directly
; =========================================================================
if (A_LineFile = A_ScriptFullPath) {
    src := '
    (
    {
      // JSONC comments need {Comments: true}
      "name": "Ali",
      "age": 30,
      "tags": ["ahk", "json", "v2"],
      "nested": { "ok": true, "none": null, "pi": 3.14159, "big": 1.5e3 },
      "users": [ {"name": "A", "id": 1}, {"name": "B", "id": 2} ],
      "text": "line1\nline2 \u00e9 \ud83d\ude00 \"quoted\""
    }
    )'

    data := JSON.Parse(src, {Preserve: true, Comments: true})

    JSON.Set(data, "nested.extra.list[1]", 42)        ; creates the missing containers
    JSON.Set(data, "users[2].admin", JSON.Bool(true))
    JSON.Delete(data, "tags[1]")

    names := JSON.Query(data, "users[*].name")
    flat := JSON.Flatten(data)
    copy := JSON.Parse(JSON.Stringify(data), {Preserve: true})

    report := "Name: " . JSON.Get(data, "name")
        . "`nPi: " . JSON.Get(data, "nested.pi")
        . "`nLast tag: " . JSON.Get(data, "tags[-1]")
        . "`nMissing (default): " . JSON.Get(data, "no.such.path", "n/a")
        . "`nUser names: " . names[1] . ", " . names[2]
        . "`nFlat keys: " . flat.Count
        . "`nRound trip equal: " . (JSON.Equals(data, copy) ? "yes" : "no")
        . "`nValid / invalid: " . JSON.IsValid("[1,2]") . " / " . JSON.IsValid("[1,2,")
        . "`n`n" . JSON.Stringify(data, 2)
    MsgBox(report, "JSON.ahk demo")

    if !JSON.TryParse('{"a": [1, 2,, 3]}', &r)
        MsgBox(JSON.LastError.Message, "Error reporting")
}
