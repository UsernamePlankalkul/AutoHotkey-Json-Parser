<h1 align="center">🧩 JSON.ahk</h1>

<p align="center">
  <b>A complete, dependency-free JSON library for AutoHotkey v2</b><br>
  Parse · Create · Manage — written from scratch in pure AHK
</p>

<p align="center">
  <img alt="AutoHotkey v2.0+" src="https://img.shields.io/badge/AutoHotkey-v2.0%2B-2ea44f?style=for-the-badge&logo=autohotkey&logoColor=white">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white">
  <img alt="Dependencies" src="https://img.shields.io/badge/Dependencies-none-ff8c00?style=for-the-badge">
  <img alt="Written from scratch" src="https://img.shields.io/badge/Parser-from%20scratch-8a2be2?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-f1c40f?style=for-the-badge">
</p>

---

## 📚 Table of contents

- [✨ Features](#-features)
- [🚀 Installation](#-installation)
- [⚡ Quick start](#-quick-start)
- [🔁 Type mapping](#-type-mapping)
- [📥 Parsing](#-parsing)
- [📤 Creating JSON](#-creating-json)
- [🎭 Literals: true, false, null](#-literals-true-false-null)
- [🧭 Paths](#-paths)
- [🛠️ Managing data](#️-managing-data)
- [📁 Files](#-files)
- [🚨 Error handling](#-error-handling)
- [⚙️ Options](#️-options)
- [📖 API reference](#-api-reference)
- [⚠️ Notes and limitations](#️-notes-and-limitations)
- [🧪 Demo](#-demo)
- [📄 License](#-license)

---

## ✨ Features

| | Feature | Details |
|---|---|---|
| 🟢 | **Full RFC 8259 parser** | Objects, arrays, strings, numbers, `true` / `false` / `null`, `\uXXXX` escapes and surrogate pairs |
| 🟢 | **Precise errors** | `JSON.ParseError` with line, column and a text excerpt |
| 🟢 | **JSONC support** | Optional `//` and `/* */` comments and trailing commas |
| 🔵 | **Pretty or compact output** | Indent by number of spaces or any string (e.g. a tab) |
| 🔵 | **Safe writer** | Circular reference detection, optional `\uXXXX` and `\/` escaping |
| 🔵 | **Hooks** | `Reviver` (while parsing), `Replacer` (while writing), `ToJSON()` on your own classes |
| 🟣 | **Path access** | `Get`, `Set`, `Has`, `Delete` with paths like `a.b[1].c` |
| 🟣 | **Wildcard queries** | `JSON.Query(data, "users[*].name")` |
| 🟣 | **Data tools** | `Merge`, `DeepClone`, `Equals`, `Flatten`, `Unflatten`, `Walk`, `Keys`, `Values`, `Count` |
| 🟠 | **Round-trip safe** | `JSON.Bool(...)` and `JSON.Null` keep `true`, `false` and `null` exact |
| 🟠 | **Zero dependencies** | One file, no COM, no external DLLs, no JavaScript engine |

---

## 🚀 Installation

> [!NOTE]
> Requires **AutoHotkey v2.0 or newer**. Developed and tested against v2.0.x.

**Option 1: next to your script**

```text
📁 my-project/
 ├─ 📄 JSON.ahk
 └─ 📄 main.ahk
```

```autohotkey
#Include JSON.ahk
```

**Option 2: as a library (no path needed)**

Put `JSON.ahk` in one of AutoHotkey's `Lib` folders (for example `<your script folder>\Lib\JSON.ahk`) and include it by name:

```autohotkey
#Include <JSON>
```

---

## ⚡ Quick start

```autohotkey
#Requires AutoHotkey v2.0
#Include JSON.ahk

; 1) Parse
text := '{"name": "Ali", "age": 30, "tags": ["ahk", "json"]}'
data := JSON.Parse(text)

MsgBox data["name"]            ; Ali
MsgBox data["tags"][2]         ; json (arrays are 1-based in AHK)

; 2) Modify
data["age"] := 31
JSON.Set(data, "address.city", "Berlin")   ; missing containers are created for you

; 3) Write
MsgBox JSON.Stringify(data, 2)             ; pretty printed with 2 spaces
```

Output of the last line:

```json
{
  "address": {
    "city": "Berlin"
  },
  "age": 31,
  "name": "Ali",
  "tags": [
    "ahk",
    "json"
  ]
}
```

> [!TIP]
> AutoHotkey Maps enumerate in **sorted key order**, which is why `address` comes first. See [Notes and limitations](#️-notes-and-limitations).

---

## 🔁 Type mapping

### ⬇️ JSON → AutoHotkey (`JSON.Parse`)

| JSON | Default result | With `{Preserve: true}` |
|---|---|---|
| object | `Map` (or plain `Object` with `{AsMap: false}`) | same |
| array | `Array` | same |
| string | `String` | same |
| integer (`42`) | `Integer` (`Float` if 19+ characters, to avoid overflow) | same |
| number (`3.14`, `1e5`) | `Float` | same |
| `true` | `1` | `JSON.Bool(true)` |
| `false` | `0` | `JSON.Bool(false)` |
| `null` | `""` (empty string) | `JSON.Null` |

### ⬆️ AutoHotkey → JSON (`JSON.Stringify`)

| AHK value | JSON output |
|---|---|
| `String` | string (**always** a string, even `"123"`) |
| `Integer`, `Float` | number (`NaN` and `Infinity` become `null`) |
| `Map`, plain `Object`, class instance | object (own properties; methods are skipped) |
| `Array` | array (unset slots become `null`) |
| `JSON.Bool(...)`, `JSON.Null` | `true`, `false`, `null` |
| object with a `ToJSON()` method | whatever `ToJSON()` returns |
| `Func` | ❌ throws `TypeError` |
| circular reference | ❌ throws `Error` |

> [!IMPORTANT]
> AHK has no real boolean type: `true` is just `1`. A plain `true` is written as `1`. Use `JSON.Bool(true)` when you need the literal `true` in the output.

---

## 📥 Parsing

```autohotkey
obj := JSON.Parse('{"a": 1, "b": [true, null, 2.5]}')
```

### Objects as plain AHK objects

```autohotkey
obj := JSON.Parse('{"user": {"name": "Ali"}}', {AsMap: false})
MsgBox obj.user.name           ; Ali
```

### Comments and trailing commas (JSONC)

```autohotkey
cfg := JSON.Parse('
(
{
    // window settings
    "width": 800,
    "height": 600,   /* trailing comma allowed below */
}
)', {Comments: true, TrailingCommas: true})
```

### Reviver: transform values while parsing

The reviver is called **bottom-up** with `(key, value)` and returns the value to keep. The root is called with an empty key.

```autohotkey
Upper(key, value) => (key = "name") ? StrUpper(value) : value

obj := JSON.Parse('{"name": "ali"}', {Reviver: Upper})
MsgBox obj["name"]             ; ALI
```

### Check text without throwing

```autohotkey
if JSON.TryParse(text, &result)
    MsgBox "Valid! Keys: " JSON.Count(result)
else
    MsgBox "Invalid: " JSON.LastError.Message

MsgBox JSON.IsValid("[1, 2, 3]")   ; 1
MsgBox JSON.IsValid("[1, 2,")      ; 0
```

---

## 📤 Creating JSON

```autohotkey
user := Map(
    "name",  "Ali",
    "admin", JSON.Bool(true),
    "score", 9.5,
    "tags",  ["a", "b"],
    "note",  JSON.Null
)

MsgBox JSON.Stringify(user)          ; compact
MsgBox JSON.Stringify(user, 4)       ; 4 spaces
MsgBox JSON.Stringify(user, "`t")    ; tabs
```

### Escaping options

```autohotkey
; "é 😀" -> "\u00e9 \ud83d\ude00"   (ASCII-only output, surrogate pairs handled)
JSON.Stringify("é 😀", , {EscapeUnicode: true})

; "a/b" -> "a\/b"   (handy when embedding JSON inside HTML <script> tags)
JSON.Stringify("a/b", , {EscapeSlash: true})

; just quote and escape one string
JSON.Quote('He said "hi"')           ; "He said \"hi\""
```

### Replacer: change or hide values while writing

```autohotkey
Hide(key, value) => (key = "password") ? "***" : value

MsgBox JSON.Stringify(Map("user", "ali", "password", "secret"), 2, {Replacer: Hide})
```

### Your own classes: `ToJSON()`

```autohotkey
class Point {
    __New(x, y) {
        this.x := x
        this.y := y
    }
    ToJSON() => Map("x", this.x, "y", this.y)
}

MsgBox JSON.Stringify(Point(3, 4))   ; {"x":3,"y":4}
```

> [!NOTE]
> Without a `ToJSON()` method, a class instance is written using its own properties.

### Reformat existing text

```autohotkey
pretty  := JSON.Prettify('{"a":1,"b":[1,2]}')        ; default indent 2
compact := JSON.Minify(pretty)                       ; {"a":1,"b":[1,2]}
```

`Prettify` and `Minify` accept comments and trailing commas in the input and drop them from the output. They also preserve `true`, `false` and `null`.

---

## 🎭 Literals: true, false, null

```diff
- Default:        true -> 1      false -> 0      null -> ""        (simple, but lossy)
+ Preserve mode:  true -> JSON.Bool(true)   false -> JSON.Bool(false)   null -> JSON.Null
```

```autohotkey
cfg := JSON.Parse('{"enabled": false, "proxy": null}', {Preserve: true})

JSON.Stringify(cfg)                          ; {"enabled":false,"proxy":null}   exact round trip

JSON.IsNull(cfg["proxy"])                    ; 1
JSON.ToNative(cfg["enabled"])                ; 0   (native AHK value)
JSON.TypeOf(cfg["enabled"])                  ; "boolean"

JSON.Set(cfg, "enabled", JSON.Bool(true))    ; write a real true
```

> [!WARNING]
> `JSON.Bool(false)` is an **object**, so it is *truthy* in an `if` test. Use `JSON.ToNative(value)` (or compare with `.Native`) when you need a plain `0` or `1`.

---

## 🧭 Paths

Paths work in `Get`, `Set`, `Has`, `Delete` and `Query`.

| Syntax | Meaning |
|---|---|
| `a.b.c` | nested keys |
| `items[1]` | array element (**1-based**) |
| `items[-1]` | last element (`-2` is second to last, and so on) |
| `$.a.b` | optional leading `$` (JSONPath style) |
| `["key.with.dots"]` or `['key']` | keys containing `.` or `[`  |
| `users[*].name` | wildcard (**`Query` only**) |
| `["a", 1, "c"]` | an `Array` of keys, no parsing needed |

```autohotkey
data := JSON.Parse('{"users": [{"name": "A"}, {"name": "B"}], "a.b": 1}')

JSON.Get(data, "users[2].name")      ; B
JSON.Get(data, "users[-1].name")     ; B
JSON.Get(data, '["a.b"]')            ; 1
JSON.Get(data, ["users", 1, "name"]) ; A
```

---

## 🛠️ Managing data

### 🔍 Get, Has

```autohotkey
JSON.Get(data, "users[1].name")                 ; returns the value
JSON.Get(data, "users[9].name", "n/a")          ; returns the default if missing
JSON.Has(data, "users[1].name")                 ; 1 or 0
```

> [!WARNING]
> `JSON.Get` throws a `ValueError` when the path does not exist **and** no default is given. Pass a default (even `""`) to avoid the exception.

### ✏️ Set

Creates missing containers automatically. `[N]` creates an **Array**, a plain name creates a **Map**.

```autohotkey
JSON.Set(data, "settings.theme", "dark")        ; creates "settings" as a Map
JSON.Set(data, "tags[1]", "first")              ; creates "tags" as an Array
JSON.Set(data, "users[3]", Map("name", "C"))    ; append (index = Length + 1)
JSON.Set(data, "users[-1].admin", JSON.Bool(true))
```

### 🗑️ Delete

```autohotkey
JSON.Delete(data, "settings.theme")   ; 1 if deleted, 0 if nothing was there
JSON.Delete(data, "users[1]")         ; removes the array element (later items shift down)
```

### 🔎 Query (wildcards)

```autohotkey
names := JSON.Query(data, "users[*].name")      ; Array of every match
for name in names
    MsgBox name
```

### 🔀 Merge

```autohotkey
base := Map("a", 1, "nested", Map("x", 1, "y", 2))
over := Map("b", 2, "nested", Map("y", 99))

JSON.Merge(base, over)        ; deep merge (default)
; base = {a:1, b:2, nested:{x:1, y:99}}

JSON.Merge(base, over, false) ; shallow: "nested" is replaced entirely
```

Two arrays at the top level are concatenated; nested arrays are replaced.

### 👯 DeepClone and Equals

```autohotkey
copy := JSON.DeepClone(data)           ; independent deep copy
MsgBox JSON.Equals(data, copy)         ; 1  (deep structural comparison)
```

`Equals` compares numbers numerically, strings case-sensitively, and treats `1` and `"1"` as different.

### 🪜 Flatten and Unflatten

```autohotkey
flat := JSON.Flatten(JSON.Parse('{"a": {"b": [10, 20]}, "c": "x"}'))
; Map: "a.b[1]" => 10,  "a.b[2]" => 20,  "c" => "x"

back := JSON.Unflatten(flat)           ; rebuilds the nested structure
```

### 🚶 Walk

Visit every node depth-first. Return `true` from the callback to stop early.

```autohotkey
Visit(path, value, parent, key) {
    if !IsObject(value)
        OutputDebug path " = " value
    return false
}

JSON.Walk(data, Visit)
```

### 🧰 Keys, Values, Count, TypeOf

```autohotkey
JSON.Keys(data)        ; Array of keys (indexes for arrays)
JSON.Values(data)      ; Array of values
JSON.Count(data)       ; number of entries
JSON.TypeOf(value)     ; "object" | "array" | "string" | "number" | "boolean" | "null"
```

---

## 📁 Files

```autohotkey
cfg := JSON.Load("config.json")                  ; read a UTF-8 file and parse it
cfg := JSON.Load("config.jsonc", {Comments: true})

cfg["lastRun"] := A_Now
JSON.Save(cfg, "config.json")                    ; indent 2, UTF-8 without BOM
JSON.Save(cfg, "config.min.json", "")            ; compact
```

---

## 🚨 Error handling

Syntax errors throw a `JSON.ParseError` with extra position info:

```autohotkey
try {
    JSON.Parse('{"a": [1, 2,, 3]}')
} catch JSON.ParseError as e {
    MsgBox e.Message                     ; message + line, column and nearby text
    MsgBox "Line " e.TextLine ", column " e.TextColumn ", position " e.TextPos
}
```

| Property | Meaning |
|---|---|
| `e.Message` | Description, plus line, column and a short excerpt |
| `e.TextLine` | 1-based line number in the JSON text |
| `e.TextColumn` | 1-based column number |
| `e.TextPos` | 1-based character position |

Other errors you may see:

| Situation | Error |
|---|---|
| Path not found in `Get` (no default) | `ValueError` |
| Invalid path syntax | `ValueError` |
| Unsupported value in `Stringify` (e.g. a function) | `TypeError` |
| Circular reference in `Stringify` | `Error` |
| Nesting deeper than `MaxDepth` | `JSON.ParseError` |

---

## ⚙️ Options

Options can be set **globally** on `JSON.Options`, or **per call** with an object (or a `Map`):

```autohotkey
JSON.Options.Comments := true                       ; global default
JSON.Parse(text, {Comments: false})                 ; per-call override
```

### Parse options

| Option | Default | Description |
|---|---|---|
| `AsMap` | `true` | Objects become `Map`. `false` gives plain `Object` (keys must not be empty) |
| `Preserve` | `false` | Keep `true` / `false` / `null` as `JSON.Bool` / `JSON.Null` |
| `Comments` | `false` | Allow `//` and `/* */` comments |
| `TrailingCommas` | `false` | Allow `[1, 2,]` and `{"a": 1,}` |
| `Strict` | `false` | Reject raw control characters inside strings |
| `MaxDepth` | `512` | Maximum nesting depth |
| `Reviver` | `""` | `fn(key, value)` called bottom-up, returns the value to keep |

### Stringify options

| Option | Default | Description |
|---|---|---|
| `EscapeUnicode` | `false` | Write non-ASCII characters as `\uXXXX` |
| `EscapeSlash` | `false` | Write `/` as `\/` |
| `Replacer` | `""` | `fn(key, value)` called before each value is written |

> [!NOTE]
> The `indent` argument of `Stringify` is separate from `opts`: a number means that many spaces (max 32), a string is used as-is, and `""` or `0` means compact.

---

## 📖 API reference

### 🟢 Parsing

| Method | Returns | Description |
|---|---|---|
| `JSON.Parse(text, opts?)` | value | Parse JSON text (alias: `JSON.Decode`) |
| `JSON.TryParse(text, &result, opts?)` | `1` / `0` | Parse without throwing; error saved in `JSON.LastError` |
| `JSON.IsValid(text, opts?)` | `1` / `0` | Syntax check |
| `JSON.Load(file, opts?, encoding?)` | value | Read and parse a file (default `UTF-8`) |

### 🔵 Creating

| Method | Returns | Description |
|---|---|---|
| `JSON.Stringify(value, indent?, opts?)` | string | Convert to JSON text (alias: `JSON.Encode`) |
| `JSON.Save(value, file, indent?, opts?, encoding?)` | | Write to a file (default indent `2`, `UTF-8-RAW`) |
| `JSON.Prettify(text, indent?)` | string | Re-indent JSON text (default `2`) |
| `JSON.Minify(text)` | string | Remove all insignificant whitespace |
| `JSON.Quote(str, opts?)` | string | Quote and escape one string |

### 🟣 Managing

| Method | Returns | Description |
|---|---|---|
| `JSON.Get(obj, path, default?)` | value | Read by path; throws if missing and no default |
| `JSON.Set(obj, path, value)` | `obj` | Write by path, creating containers as needed |
| `JSON.Has(obj, path)` | `1` / `0` | Does the path exist? |
| `JSON.Delete(obj, path)` | `1` / `0` | Remove by path |
| `JSON.Query(obj, path)` | Array | All matches for a path with `*` wildcards |
| `JSON.Merge(target, source, deep?)` | `target` | Merge `source` into `target` (default deep) |
| `JSON.DeepClone(value)` | value | Recursive copy |
| `JSON.Equals(a, b)` | `1` / `0` | Deep comparison |
| `JSON.Flatten(obj)` | Map | `path => leaf value` |
| `JSON.Unflatten(map)` | value | Inverse of `Flatten` |
| `JSON.Walk(obj, fn)` | | Visit all nodes with `fn(path, value, parent, key)` |
| `JSON.Keys(obj)` / `JSON.Values(obj)` / `JSON.Count(obj)` | Array / Array / Integer | Container helpers |

### 🟠 Literals and types

| Member | Description |
|---|---|
| `JSON.Null` | The JSON `null` literal |
| `JSON.Bool(v)` | The JSON `true` or `false` literal, depending on `v` |
| `JSON.IsNull(v)` | `1` if `v` is `JSON.Null` |
| `JSON.ToNative(v)` | Convert a literal to `1` / `0` / `""`; other values are returned unchanged |
| `JSON.TypeOf(v)` | `"object"`, `"array"`, `"string"`, `"number"`, `"boolean"` or `"null"` |
| `JSON.Options` | Global default options |
| `JSON.LastError` | Last error stored by `TryParse` / `IsValid` |
| `JSON.ParseError` | Error class thrown on invalid JSON |

---

## ⚠️ Notes and limitations

> [!WARNING]
> **Key order is not preserved.** AHK Maps enumerate in sorted key order, so `Stringify` writes object keys sorted (numbers first, then strings). Object keys never keep their original order from the source text.

- **Arrays are 1-based** everywhere, including in paths (`items[1]` is the first element).
- **Numeric dotted segments are keys, not indexes.** `a.0` means the *key* `"0"`; write `a[1]` for array elements. This matters in `Set`, which decides between creating a `Map` and an `Array`.
- **Large integers.** Integers with 19 or more characters are returned as `Float` to avoid `Int64` overflow, so they can lose precision.
- **Strings stay strings.** The writer uses AHK's real types: the string `"42"` is written as `"42"` and the integer `42` as `42`.
- **Plain objects (`AsMap: false`) cannot hold empty keys**, and Maps are the safer choice for arbitrary JSON.
- **Text encoding.** `Load` reads UTF-8 and `Save` writes UTF-8 without a BOM. A leading BOM in the text is ignored by the parser.

---

## 🧪 Demo

Run `JSON.ahk` directly (double-click it, or `AutoHotkey64.exe JSON.ahk`) to see a built-in demo that parses, edits, queries, flattens, round-trips and pretty prints a sample document, then shows a parse error message.

---

## 📄 License

Released under the **MIT License**. Replace this section with your own license text if you prefer a different one.

<p align="center">
  Made with 💚 and a lot of <code>SubStr()</code> · Pull requests and issues are welcome
</p>
