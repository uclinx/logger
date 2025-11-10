print("SCRIPT START OK")
-- Send_PetsAndMoney_ToWebhook.lua (patched to post IDs to realtime API)
-- Gathers pet data, sends a webhook if pets meet the threshold, then hops to a new server.

-- ====== CONFIG ======
local API_POST = "https://api.pixells.sbs/ids"      -- realtime server endpoint
local API_TOKEN = "PXL-23bda7f4-8eac-4a5a-a1d2-logger"   -- Render/VPS token
-- ====================

local WEBHOOK_URL = "https://discord.com/api/webhooks/1437468340783419623/utoeRw4LzXQHq6FzTFbbKHlw8R5O55fO25ASbMCS3UNA90qOPelCDbRJFU0YyZC23lrj"
local USERNAME = "Pixells Log"
local EMBED_COLOR = 0xFFFFFF 
local MINIMUM_MONEY_THRESHOLD = 10000000 -- 10M/s threshold

-- === Ignore list ===
local ignoreList = {
    "FriendPanel", "Model", "Decorations", "Claim",
    "Stolen", "Gold", "Diamond", "Yin Yang",
    "Rainbow", "Brainrot God", "Mythic", "Secret", "OG"
}
local function isIgnored(name)
    if not name or type(name) ~= "string" then return false end
    for _, ig in ipairs(ignoreList) do 
        if name == ig or name:lower() == ig:lower() then return true end 
    end
    return false
end

-- === JSON builder ===
local function escape_json_str(s)
    s = tostring(s or "")
    return s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
end

local function build_body(tbl)
    local function enc(v)
        if type(v) == "string" then return '"' .. escape_json_str(v) .. '"' end
        if type(v) == "number" or type(v) == "boolean" then return tostring(v) end
        if type(v) == "table" then
            if #v > 0 then
                local t = {}
                for i=1,#v do t[#t+1] = enc(v[i]) end
                return "[" .. table.concat(t, ",") .. "]"
            else
                local t = {}
                for k,val in pairs(v) do t[#t+1] = '"'..escape_json_str(k)..'":'..enc(val) end
                return "{" .. table.concat(t, ",") .. "}"
            end
        end
        return "null"
    end
    local parts = {}
    for k,v in pairs(tbl) do parts[#parts+1] = '"'..escape_json_str(k)..'":'..enc(v) end
    return "{"..table.concat(parts, ",").."}"
end

-- === HTTP utils ===
local function try_http_request(req_table)
    local methods = {
        function() return syn and syn.request and syn.request(req_table) end,
        function() return http and http.request and http.request(req_table) end,
        function() return request and request(req_table) end,
        function() return http_request and http_request(req_table) end
    }
    for _, f in ipairs(methods) do
        local ok, res = pcall(f)
        if ok and res then return true, res end
    end
    return false, "no executor HTTP support"
end

-- === New: send IDs to realtime server ===
local function post_ids_array(ids_array, source)
    if not ids_array or #ids_array == 0 then return false, "no ids" end
    local payload = {
        ids = ids_array,
        source = source or "pixells",
        ts = os.time()
    }
    local body = build_body(payload)
    local req = {
        Url = API_POST,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
            ["Authorization"] = "Bearer " .. API_TOKEN
        },
        Body = body
    }
    local ok, res_or_err = try_http_request(req)
    if not ok then return false, tostring(res_or_err) end
    local sc = res_or_err.StatusCode or res_or_err.statusCode
    if sc and sc >= 200 and sc < 300 then
        return true
    else
        return false, "HTTP " .. tostring(sc)
    end
end

-- === Formatting ===
local function format_number(n)
    if n >= 1e12 then return string.format("%.1fT/s", n/1e12)
    elseif n >= 1e9 then return string.format("%.1fB/s", n/1e9)
    elseif n >= 1e6 then return string.format("%.1fM/s", n/1e6)
    elseif n >= 1e3 then return string.format("%.1fK/s", n/1e3)
    else return tostring(math.floor(n)).."/s" end
end

-- === Main ===
print("Waiting for LocalPlayer...")
local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer
while not localPlayer do task.wait(0.1) localPlayer = Players.LocalPlayer end
if not localPlayer.Character or not localPlayer.Character.Parent then
    localPlayer.CharacterAdded:Wait()
end

print("Character loaded. Waiting for game to finish loading...")
if not game:IsLoaded() then
    if game.Loaded then game.Loaded:Wait() else while not game:IsLoaded() do task.wait(0.1) end end
end
wait(2)

print("Game fully loaded. Starting scan...")

-- 🐾 Example mock IDs (replace with your actual logic from scan)
local jobId = game.JobId or "N/A"
local ids_to_send = { jobId .. "|test.plot.1|Dragon|9999999" }

local ok_post, post_res = post_ids_array(ids_to_send, "pixells")
if not ok_post then
    print("⚠ Failed to POST IDs:", post_res)
else
    print("✅ Posted IDs to realtime server:", #ids_to_send)
end
