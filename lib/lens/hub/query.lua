--[[ lens.hub.query: the hub's small selector language, for dashboards, the HUD and alert rules. Pure.

  local q, err = require("lens.hub.query").compile('sum(prism_machine_state{process="ore", state="running"})')
  q(lookup) -> number | nil       lookup(metricName) -> series[] (store:lookup bound to `now`)

  Grammar (Lua-like precedence, loosest first):
    expr     := and { "or" and }
    and      := not { "and" not }
    not      := [ "not" ] cmp
    cmp      := sum [ ("<" | "<=" | ">" | ">=" | "==" | "!=") sum ]
    sum      := product { ("+" | "-") product }
    product  := unary { ("*" | "/") unary }
    unary    := [ "-" ] atom
    atom     := number | "(" expr ")" | func "(" selector ")" | selector
    func     := sum | count | max | min | avg | rate
    selector := name [ "{" matcher { "," matcher } "}" ]
    matcher  := label ("=" | "!=" | "=~" | "!~") "string"

  Values:
    selector alone   the sum of the matching series; nil when none match
    sum/max/min/avg  over the matching series; nil when none match
    count            how many series match (0 when none)
    rate             summed per-second rates of matching counters; nil when none has a rate yet
    =~ and !~        Lua patterns, unanchored (use ^ and $), against the label's value ("" when missing)
    comparisons      1 or 0; nil if either side is nil
    and, or, not     1 or 0; nil and 0 count as false (missing data never fires a rule)
    a / 0            nil
  Every series has a `node` label (added by the hub), so node="prism-ore" selects one node's series.
]]

local query = {}

---------------------------------------------------------------- tokens
local SYMBOLS = { "<=", ">=", "==", "!=", "=~", "!~", "(", ")", "{", "}", ",", "+", "-", "*", "/", "<", ">", "=" }
local KEYWORDS = { ["and"] = true, ["or"] = true, ["not"] = true }

local function tokenize(text)
  local toks, i = {}, 1
  while i <= #text do
    local c = text:sub(i, i)
    if c:find("%s") then
      i = i + 1
    elseif c:find("[%d%.]") then
      local num = text:match("^%d*%.?%d+[eE][%+%-]?%d+", i) or text:match("^%d*%.?%d*", i)
      local v = tonumber(num)
      if not v then return nil, ("bad number at %d"):format(i) end
      toks[#toks + 1] = { t = "num", v = v, at = i }
      i = i + #num
    elseif c:find("[%a_]") then
      local word = text:match("^[%w_]+", i)
      toks[#toks + 1] = { t = KEYWORDS[word] and word or "name", v = word, at = i }
      i = i + #word
    elseif c == '"' or c == "'" then
      local j, buf = i + 1, {}
      while j <= #text and text:sub(j, j) ~= c do
        if text:sub(j, j) == "\\" then j = j + 1 end
        buf[#buf + 1] = text:sub(j, j)
        j = j + 1
      end
      if j > #text then return nil, ("unterminated string at %d"):format(i) end
      toks[#toks + 1] = { t = "str", v = table.concat(buf), at = i }
      i = j + 1
    else
      local sym
      for _, s in ipairs(SYMBOLS) do
        if text:sub(i, i + #s - 1) == s then sym = s; break end
      end
      if not sym then return nil, ("unexpected '%s' at %d"):format(c, i) end
      toks[#toks + 1] = { t = sym, at = i }
      i = i + #sym
    end
  end
  toks[#toks + 1] = { t = "eof", at = #text + 1 }
  return toks
end

---------------------------------------------------------------- parsing into closures
local AGGREGATE = {
  sum = function(list)
    if #list == 0 then return nil end
    local t = 0
    for _, s in ipairs(list) do t = t + s.value end
    return t
  end,
  count = function(list) return #list end,
  max = function(list)
    local m
    for _, s in ipairs(list) do if not m or s.value > m then m = s.value end end
    return m
  end,
  min = function(list)
    local m
    for _, s in ipairs(list) do if not m or s.value < m then m = s.value end end
    return m
  end,
  avg = function(list)
    if #list == 0 then return nil end
    local t = 0
    for _, s in ipairs(list) do t = t + s.value end
    return t / #list
  end,
  rate = function(list)
    local t
    for _, s in ipairs(list) do if s.rate then t = (t or 0) + s.rate end end
    return t
  end,
}

local function truthy(v) return v ~= nil and v ~= 0 end

local BINARY = {
  ["+"] = function(a, b) if a and b then return a + b end end,
  ["-"] = function(a, b) if a and b then return a - b end end,
  ["*"] = function(a, b) if a and b then return a * b end end,
  ["/"] = function(a, b) if a and b and b ~= 0 then return a / b end end,
  ["<"] = function(a, b) if a and b then return a < b and 1 or 0 end end,
  ["<="] = function(a, b) if a and b then return a <= b and 1 or 0 end end,
  [">"] = function(a, b) if a and b then return a > b and 1 or 0 end end,
  [">="] = function(a, b) if a and b then return a >= b and 1 or 0 end end,
  ["=="] = function(a, b) if a and b then return a == b and 1 or 0 end end,
  ["!="] = function(a, b) if a and b then return a ~= b and 1 or 0 end end,
}

local MATCH = {
  ["="] = function(v, x) return v == x end,
  ["!="] = function(v, x) return v ~= x end,
  ["=~"] = function(v, x) return v:find(x) ~= nil end,
  ["!~"] = function(v, x) return v:find(x) == nil end,
}

local Parser = {}
Parser.__index = Parser

function Parser:peek() return self.toks[self.i] end
function Parser:next()
  local t = self.toks[self.i]
  self.i = self.i + 1
  return t
end
function Parser:fail(msg, tok)
  tok = tok or self:peek()
  error({ msg = ("%s at %d"):format(msg, tok.at) }, 0)
end
function Parser:expect(t, what)
  local tok = self:next()
  if tok.t ~= t then self:fail("expected " .. (what or t), tok) end
  return tok
end

function Parser:selector()
  local name = self:expect("name", "a metric name").v
  local matchers = {}
  if self:peek().t == "{" then
    self:next()
    while true do
      local label = self:expect("name", "a label name").v
      local op = self:next()
      if not MATCH[op.t] then self:fail("expected =, !=, =~ or !~", op) end
      local value = self:expect("str", "a quoted value").v
      if op.t == "=~" or op.t == "!~" then
        if not pcall(string.find, "", value) then self:fail("bad pattern " .. value, op) end
      end
      matchers[#matchers + 1] = { label = label, test = MATCH[op.t], value = value }
      if self:peek().t ~= "," then break end
      self:next()
    end
    self:expect("}")
  end
  return function(lookup)
    local out = {}
    for _, s in ipairs(lookup(name) or {}) do
      local ok = true
      for _, m in ipairs(matchers) do
        if not m.test(s.labels[m.label] or "", m.value) then ok = false; break end
      end
      if ok then out[#out + 1] = s end
    end
    return out
  end
end

function Parser:atom()
  local tok = self:peek()
  if tok.t == "num" then
    self:next()
    local v = tok.v
    return function() return v end
  elseif tok.t == "(" then
    self:next()
    local e = self:expr()
    self:expect(")")
    return e
  elseif tok.t == "name" then
    local nxt = self.toks[self.i + 1]
    if AGGREGATE[tok.v] and nxt.t == "(" then
      self:next(); self:next()
      local sel = self:selector()
      self:expect(")")
      local agg = AGGREGATE[tok.v]
      return function(lookup) return agg(sel(lookup)) end
    end
    local sel = self:selector()
    local sum = AGGREGATE.sum
    return function(lookup) return sum(sel(lookup)) end
  end
  self:fail("expected a number, metric or (", tok)
end

function Parser:unary()
  if self:peek().t == "-" then
    self:next()
    local a = self:unary()
    return function(l) local v = a(l); return v and -v end
  end
  return self:atom()
end

function Parser:binary(sub, ops)
  local left = sub(self)
  while ops[self:peek().t] do
    local f = BINARY[self:next().t]
    local a, b = left, sub(self)
    left = function(l) return f(a(l), b(l)) end
  end
  return left
end

local PRODUCT = { ["*"] = true, ["/"] = true }
local SUM = { ["+"] = true, ["-"] = true }
local CMP = { ["<"] = true, ["<="] = true, [">"] = true, [">="] = true, ["=="] = true, ["!="] = true }

function Parser:product() return self:binary(Parser.unary, PRODUCT) end
function Parser:sum() return self:binary(Parser.product, SUM) end

function Parser:cmp()
  local left = self:sum()
  if CMP[self:peek().t] then
    local f = BINARY[self:next().t]
    local a, b = left, self:sum()
    return function(l) return f(a(l), b(l)) end
  end
  return left
end

function Parser:notExpr()
  if self:peek().t == "not" then
    self:next()
    local a = self:cmp()
    return function(l) return truthy(a(l)) and 0 or 1 end
  end
  return self:cmp()
end

function Parser:andExpr()
  local left = self:notExpr()
  while self:peek().t == "and" do
    self:next()
    local a, b = left, self:notExpr()
    left = function(l) return (truthy(a(l)) and truthy(b(l))) and 1 or 0 end
  end
  return left
end

function Parser:expr()
  local left = self:andExpr()
  while self:peek().t == "or" do
    self:next()
    local a, b = left, self:andExpr()
    left = function(l) return (truthy(a(l)) or truthy(b(l))) and 1 or 0 end
  end
  return left
end

function query.compile(text)
  if type(text) ~= "string" then return nil, "query must be a string" end
  local toks, err = tokenize(text)
  if not toks then return nil, err end
  local p = setmetatable({ toks = toks, i = 1 }, Parser)
  local ok, res = pcall(function()
    local e = p:expr()
    p:expect("eof", "end of query")
    return e
  end)
  if not ok then
    if type(res) == "table" then return nil, res.msg end
    error(res, 0)
  end
  return res
end

return query
