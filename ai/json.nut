/*
 * This file is part of JevTTD.
 *
 * JevTTD is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * JevTTD is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

/**
 * @file json.nut Minimal JSON encoder/decoder. OpenTTD's Squirrel API has no
 * built-in JSON support (see AIAdmin::Send in the engine, which does its own
 * table->JSON conversion in C++ for the exact same reason), so this is a
 * small hand-rolled one just for talking to a Jev-compatible decision
 * service (see funbrain.nut). Not a general-purpose JSON library: it covers
 * only what System One requests/responses actually need - strings, numbers,
 * bools, null, arrays, and (string-keyed) objects. No unicode escapes beyond
 * the required control characters, no big-number precision guarantees.
 */

class Json {
	/**
	 * Encode a Squirrel value (string/integer/float/bool/null/array/table)
	 * as JSON text.
	 */
	static function Encode(value);

	/**
	 * Decode a JSON string into Squirrel values (string/integer or
	 * float/bool/null/array/table). Throws a string error on malformed
	 * input.
	 */
	static function Decode(text);

	/* Private-ish helpers, exposed only because Squirrel classes have no
	 * real access control; not part of this file's public surface. */
	static function EncodeString(s);
	static function HexDigit(nibble);
	static function ToHex4(code);
}

function Json::HexDigit(nibble)
{
	if (nibble < 10) return (48 + nibble).tochar(); // '0'-'9'
	return (87 + nibble).tochar(); // 'a'-'f'
}

function Json::ToHex4(code)
{
	local out = "";
	for (local shift = 12; shift >= 0; shift -= 4) {
		out += Json.HexDigit((code >> shift) & 0xF);
	}
	return out;
}

function Json::EncodeString(s)
{
	local out = "\"";
	local len = s.len();
	for (local i = 0; i < len; i++) {
		local c = s.slice(i, i + 1);
		if (c == "\"") { out += "\\\""; }
		else if (c == "\\") { out += "\\\\"; }
		else if (c == "\n") { out += "\\n"; }
		else if (c == "\r") { out += "\\r"; }
		else if (c == "\t") { out += "\\t"; }
		else {
			local code = s[i];
			if (code < 0x20) {
				out += "\\u" + Json.ToHex4(code);
			} else {
				out += c;
			}
		}
	}
	return out + "\"";
}

function Json::Encode(value)
{
	local t = typeof(value);
	if (t == "null") return "null";
	if (t == "bool") return value ? "true" : "false";
	if (t == "integer" || t == "float") return value.tostring();
	if (t == "string") return Json.EncodeString(value);

	if (t == "array") {
		local parts = [];
		foreach (v in value) parts.push(Json.Encode(v));
		return "[" + ",".join(parts) + "]";
	}

	if (t == "table") {
		local parts = [];
		foreach (k, v in value) {
			parts.push(Json.EncodeString(k.tostring()) + ":" + Json.Encode(v));
		}
		return "{" + ",".join(parts) + "}";
	}

	throw ("Json.Encode: unsupported type '" + t + "'");
}

/* --- Decoder --- */

class JsonParser {
	text = null;
	pos = 0;

	constructor(text)
	{
		this.text = text;
		this.pos = 0;
	}

	function Parse();

	function SkipWhitespace();
	function Peek();
	function Expect(ch);
	function ParseValue();
	function ParseString();
	function ParseNumber();
	function ParseObject();
	function ParseArray();
	function ParseLiteral(literal, value);
}

function JsonParser::SkipWhitespace()
{
	while (this.pos < this.text.len()) {
		local c = this.text.slice(this.pos, this.pos + 1);
		if (c != " " && c != "\t" && c != "\n" && c != "\r") break;
		this.pos++;
	}
}

function JsonParser::Peek()
{
	if (this.pos >= this.text.len()) return "";
	return this.text.slice(this.pos, this.pos + 1);
}

function JsonParser::Expect(ch)
{
	if (this.Peek() != ch) throw ("Json.Decode: expected '" + ch + "' at offset " + this.pos);
	this.pos++;
}

function JsonParser::Parse()
{
	this.SkipWhitespace();
	local v = this.ParseValue();
	this.SkipWhitespace();
	return v;
}

function JsonParser::ParseValue()
{
	this.SkipWhitespace();
	local c = this.Peek();
	if (c == "\"") return this.ParseString();
	if (c == "{") return this.ParseObject();
	if (c == "[") return this.ParseArray();
	if (c == "t") return this.ParseLiteral("true", true);
	if (c == "f") return this.ParseLiteral("false", false);
	if (c == "n") return this.ParseLiteral("null", null);
	if (c == "-" || (c >= "0" && c <= "9")) return this.ParseNumber();
	throw ("Json.Decode: unexpected character '" + c + "' at offset " + this.pos);
}

function JsonParser::ParseLiteral(literal, value)
{
	local end = this.pos + literal.len();
	if (this.text.slice(this.pos, end) != literal) {
		throw ("Json.Decode: expected '" + literal + "' at offset " + this.pos);
	}
	this.pos = end;
	return value;
}

function JsonParser::ParseString()
{
	this.Expect("\"");
	local out = "";
	while (true) {
		local c = this.Peek();
		if (c == "") throw "Json.Decode: unterminated string";
		this.pos++;
		if (c == "\"") break;
		if (c == "\\") {
			local esc = this.Peek();
			this.pos++;
			if (esc == "n") out += "\n";
			else if (esc == "r") out += "\r";
			else if (esc == "t") out += "\t";
			else if (esc == "\"") out += "\"";
			else if (esc == "\\") out += "\\";
			else if (esc == "/") out += "/";
			else if (esc == "u") {
				/* Only handle the common case (BMP code point, no
				 * surrogate pairs) - System One responses are not
				 * expected to need more than that. */
				local hex = this.text.slice(this.pos, this.pos + 4);
				this.pos += 4;
				local code = 0;
				foreach (ch in hex) {
					code = code * 16;
					if (ch >= '0' && ch <= '9') code += ch - '0';
					else if (ch >= 'a' && ch <= 'f') code += ch - 'a' + 10;
					else if (ch >= 'A' && ch <= 'F') code += ch - 'A' + 10;
				}
				out += code.tochar();
			} else {
				out += esc;
			}
		} else {
			out += c;
		}
	}
	return out;
}

function JsonParser::ParseNumber()
{
	local start = this.pos;
	if (this.Peek() == "-") this.pos++;
	while (this.Peek() >= "0" && this.Peek() <= "9") this.pos++;
	local is_float = false;
	if (this.Peek() == ".") {
		is_float = true;
		this.pos++;
		while (this.Peek() >= "0" && this.Peek() <= "9") this.pos++;
	}
	if (this.Peek() == "e" || this.Peek() == "E") {
		is_float = true;
		this.pos++;
		if (this.Peek() == "+" || this.Peek() == "-") this.pos++;
		while (this.Peek() >= "0" && this.Peek() <= "9") this.pos++;
	}
	local s = this.text.slice(start, this.pos);
	return is_float ? s.tofloat() : s.tointeger();
}

function JsonParser::ParseObject()
{
	this.Expect("{");
	local obj = {};
	this.SkipWhitespace();
	if (this.Peek() == "}") { this.pos++; return obj; }
	while (true) {
		this.SkipWhitespace();
		local key = this.ParseString();
		this.SkipWhitespace();
		this.Expect(":");
		local value = this.ParseValue();
		obj.rawset(key, value);
		this.SkipWhitespace();
		local c = this.Peek();
		if (c == ",") { this.pos++; continue; }
		if (c == "}") { this.pos++; break; }
		throw ("Json.Decode: expected ',' or '}' at offset " + this.pos);
	}
	return obj;
}

function JsonParser::ParseArray()
{
	this.Expect("[");
	local arr = [];
	this.SkipWhitespace();
	if (this.Peek() == "]") { this.pos++; return arr; }
	while (true) {
		local value = this.ParseValue();
		arr.push(value);
		this.SkipWhitespace();
		local c = this.Peek();
		if (c == ",") { this.pos++; continue; }
		if (c == "]") { this.pos++; break; }
		throw ("Json.Decode: expected ',' or ']' at offset " + this.pos);
	}
	return arr;
}

function Json::Decode(text)
{
	local parser = JsonParser(text);
	return parser.Parse();
}
