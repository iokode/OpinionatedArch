// Line tokenizer for the map syntax. Every entry fits on one physical line, so
// the lexer never carries state between lines.

class Token {
    kind: "word" | "str" | "sym",
    text: string,
}

/// True for the characters that separate tokens or carry their own meaning.
function is_delimiter(c: string) -> bool {
    c == " "
        || c == "\t"
        || c == "\r"
        || c == "'"
        || c == "#"
        || c == "="
        || c == ","
        || c == "["
        || c == "]"
}

/// Splits one physical line into tokens. An unquoted `#` starts a comment that
/// runs to the end of the line; a `#` inside a quoted value is literal text.
function tokenize_line(line: string, loc: SourceLoc, diag: Diagnostics) -> Token[] {
    let chars = line.chars();
    let count = chars.length();
    let tokens: Token[] = [];
    let i = 0;
    while (i < count) {
        let c = chars.at(i) ?? "";
        if (c == "#") {
            i = count;
        } else if (c == " " || c == "\t" || c == "\r") {
            i = i + 1;
        } else if (c == "'") {
            //# quoted value: `\'` is the only escape
            let text = "";
            let j = i + 1;
            let closed = false;
            while (j < count && !closed) {
                let d = chars.at(j) ?? "";
                if (d == "\\" && (chars.at(j + 1) ?? "") == "'") {
                    text = text + "'";
                    j = j + 2;
                } else if (d == "'") {
                    closed = true;
                    j = j + 1;
                } else {
                    text = text + d;
                    j = j + 1;
                }
            }
            if (!closed) {
                diag.at(loc, "unterminated quoted value");
            }
            let _ = tokens.push(Token { kind: "str", text: text });
            i = j;
        } else if (c == "=" || c == "," || c == "[" || c == "]") {
            let _ = tokens.push(Token { kind: "sym", text: c });
            i = i + 1;
        } else {
            let text = "";
            let j = i;
            while (j < count && !is_delimiter(chars.at(j) ?? "")) {
                text = text + (chars.at(j) ?? "");
                j = j + 1;
            }
            let _ = tokens.push(Token { kind: "word", text: text });
            i = j;
        }
    }
    tokens
}

/// A bounded read cursor over a token array.
class Cursor {
    tokens: Token[],
    pos: int,
    limit: int,

    function peek(self) -> Token? {
        if (self.pos < self.limit) {
            self.tokens.at(self.pos)
        } else {
            null
        }
    }

    function advance(self) -> Token? {
        let token = self.peek();
        if (token != null) {
            self.pos = self.pos + 1;
        }
        token
    }

    function at_end(self) -> bool {
        self.pos >= self.limit
    }

    /// The next token when it is a word with the given text, consumed.
    function take_word(self, text: string) -> bool {
        if let token: Token = self.peek() {
            if (token.kind == "word" && token.text == text) {
                self.pos = self.pos + 1;
                true
            } else {
                false
            }
        } else {
            false
        }
    }
}

function new_cursor(tokens: Token[], pos: int, limit: int) -> Cursor {
    Cursor { tokens: tokens, pos: pos, limit: limit }
}

test "tokenize entries" {
    let diag = new_diagnostics();
    let loc = SourceLoc { file: "t.dfmap", line: 1 };

    let plain = tokenize_line("link 'a/b.lua' to '&HOME/.config/b.lua'", loc, diag);
    assert.equal(plain.length(), 4);
    assert.equal(plain.at(0)?.kind ?? "", "word");
    assert.equal(plain.at(1)?.text ?? "", "a/b.lua");
    assert.equal(plain.at(3)?.text ?? "", "&HOME/.config/b.lua");

    let commented = tokenize_line("hyprland # a comment with 'quotes'", loc, diag);
    assert.equal(commented.length(), 1);
    assert.equal(commented.at(0)?.text ?? "", "hyprland");

    let hashed = tokenize_line("color = '#ff0000'", loc, diag);
    assert.equal(hashed.length(), 3);
    assert.equal(hashed.at(2)?.text ?? "", "#ff0000");

    let escaped = tokenize_line("name = 'it\\'s mine'", loc, diag);
    assert.equal(escaped.at(2)?.text ?? "", "it's mine");

    let header = tokenize_line("[dotfiles.hypr for host 'desktop','laptop']", loc, diag);
    assert.equal(header.length(), 8);
    assert.equal(header.at(0)?.text ?? "", "[");
    assert.equal(header.at(7)?.text ?? "", "]");

    let composed = tokenize_line("render 'a.tpl' + 'b.tpl' to 'x'", loc, diag);
    assert.equal(composed.length(), 6);
    assert.equal(composed.at(2)?.text ?? "", "+");

    assert.is_true(!diag.has_errors())
}
