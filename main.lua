-- CONFIG
local API_POST = "https://api.pixells.sbs/ids"
local API_TOKEN = "PXL-23bda7f4-8eac-4a5a-a1d2-logger"

local WEBHOOK_URL = "https://discord.com/api/webhooks/1437810721252704307/f-RpaCE0msTrEe4ZpesAkvrJMo-7ivJ_AiNlfjdhyz8Y8FUkfpcQxY-p-vJnZ9901RtL"
local USERNAME = "Pixells Log"
local EMBED_COLOR = 0xFFFFFF
local MINIMUM_MONEY_THRESHOLD = 1

local ignoreList = {
    "FriendPanel",
    "Model",
    "Decorations",
    "Claim",
    "Stolen",
    "Gold",
    "Diamond",
    "Yin Yang",
    "Rainbow",
    "Brainrot God",
    "Mythic",
    "Secret",
    "OG"
}
local function isIgnored(name)
    if not name or type(name) ~= "string" then return false end
    for _, ig in ipairs(ignoreList) do
        if name == ig or name:lower() == ig:lower() then return true end
    end
    return false
end

local function escape_json_str(s)
    s = tostring(s or "")
    s = s:gsub("\\","\\\\"):gsub('"','\\"'):gsub("\n","\\n"):gsub("\r","\\r"):gsub("\t","\\t")
    return s
end

local function build_body(tbl)
    local parts = {"{"}
    local first = true
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
    for k,v in pairs(tbl) do
        if not first then table.insert(parts, ",") end
        first = false
        table.insert(parts, '"' .. escape_json_str(k) .. '":' .. enc(v))
    end
    table.insert(parts, "}")
    return table.concat(parts)
end

local function try_http_request(req_table)
    local errors = {}
    if type(syn) == "table" and type(syn.request) == "function" then
        local ok, res = pcall(function() return syn.request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "syn.request")
    end
    if type(http) == "table" and type(http.request) == "function" then
        local ok, res = pcall(function() return http.request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "http.request")
    end
    if type(request) == "function" then
        local ok, res = pcall(function() return request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "request")
    end
    if type(http_request) == "function" then
        local ok, res = pcall(function() return http_request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "http_request")
    end
    return false, "No supported HTTP client found or request failed. Tried: " .. table.concat(errors, ", ")
end

local function post_ids_array(ids_array, source)
    if not ids_array or #ids_array == 0 then
        return false, "no ids to send"
    end

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
            ["Authorization"] = "Bearer " .. tostring(API_TOKEN)
        },
        Body = body
    }

    local ok, res_or_err = try_http_request(req)

    if not ok then
        return false, "HTTP request failed: " .. tostring(res_or_err)
    end

    if type(res_or_err) == "table" then
        local status_code = res_or_err.StatusCode or res_or_err.statusCode or res_or_err.code or 0
        local res_body = res_or_err.Body or res_or_err.body or res_or_err.Response or "no body provided"

        if status_code >= 200 and status_code < 300 then
            return true, res_or_err
        else
            return false, "API HTTP " .. tostring(status_code) .. " - " .. tostring(res_body)
        end
    end

    return true, res_or_err
end

local function send_discord_embed(embed_data, username)
    local payload = {
        username = username or USERNAME,
        embeds = {embed_data}
    }
    local body = build_body(payload)
    local req = {
        Url = WEBHOOK_URL,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = tostring(#body),
        },
        Body = body
    }
    local ok, res_or_err = try_http_request(req)
    if not ok then
        local fallback_msg = "❌ Failed to send Embed. Error: " .. tostring(res_or_err)
        return false, fallback_msg
    end
    return true
end

local function format_number(n)
    if n >= 1e12 then
        return string.format("%.1fT/s", n / 1e12)
    elseif n >= 1e9 then
        return string.format("%.1fB/s", n / 1e9)
    elseif n >= 1e6 then
        return string.format("%.1fM/s", n / 1e6)
    elseif n >= 1e3 then
        return string.format("%.1fK/s", n / 1e3)
    else
        return tostring(math.floor(n)) .. "/s"
    end
end

local function parse_money_per_sec(text)
    if type(text) ~= "string" then return nil end
    local t = text:match("^%s*(.-)%s*$") or text
    local before = t:match("^(.-)/s") or t:match("^(.-)/sec") or t:match("^(.-)per%s?s") or t
    before = before:gsub("[,%s]", ""):gsub("%$", "")
    local numStr, suffix = before:match("^([%+%-]?%d+%.?%d*)([kKmMbB]?)$")
    if not numStr then
        numStr = before:match("([%+%-]?%d+%.?%d*)")
        suffix = before:match("%a$") or ""
    end
    if not numStr then return nil end
    local n = tonumber(numStr)
    if not n then return nil end
    local s = (suffix or ""):lower()
    if s == "k" then n = n * 1e3
    elseif s == "m" then n = n * 1e6
    elseif s == "b" then n = n * 1e9
    end
    return n
end

local function try_get_text(inst)
    local ok, v = pcall(function() return inst.Text end)
    if ok and type(v) == "string" and v ~= "" then return v end
    return nil
end

local function find_nearest_model(inst)
    local cur = inst
    while cur and cur.Parent do
        if cur:IsA("Model") then return cur end
        cur = cur.Parent
    end
    return nil
end

local function is_uuid_like_short(s)
    if type(s) ~= "string" then return false end
    return s:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x") ~= nil
end

local function extract_name_from_podium(podium)
    if not podium then return nil end
    for _, d in ipairs(podium:GetDescendants()) do
        if d:IsA("Model") then

            local sv = d:FindFirstChild("PetName", true) or d:FindFirstChild("Name", true) or d:FindFirstChild("DisplayName", true)

            local name_val = nil
            if sv then
                if sv:IsA("StringValue") or sv:IsA("NumberValue") then
                    name_val = tostring(sv.Value)
                elseif sv:IsA("TextLabel") or sv:IsA("TextBox") then
                    name_val = sv.Text
                end
            end

            if name_val and name_val:match("%S") and not is_uuid_like_short(name_val) and not isIgnored(name_val) then
                return name_val
            end

            if d.Name and d.Name ~= "Base" and d.Name ~= "Model" and not is_uuid_like_short(d.Name) and not isIgnored(d.Name) then
                return d.Name
            end
        end
    end
    local info = podium:FindFirstChild("Info") or podium:FindFirstChild("info")
    if info then
        for _,c in ipairs(info:GetDescendants()) do
            if c:IsA("StringValue") and c.Value and c.Value:match("%S") and not is_uuid_like_short(c.Value) and not isIgnored(c.Value) then return c.Value end
        end
    end
    for _, b in ipairs(podium:GetDescendants()) do
        if b:IsA("BillboardGui") or b:IsA("SurfaceGui") then
            for _, child in ipairs(b:GetDescendants()) do
                if child:IsA("TextLabel") or child:IsA("TextBox") then
                    local ok, txt = pcall(function() return child.Text end)
                    if ok and type(txt) == "string" and txt:match("%S") and not txt:match("%d+%s*[/]s") and not txt:match("%$?%d") and not is_uuid_like_short(txt) then
                        local token = txt:match("([A-Za-z][A-Za-z%s'%-]+)")
                        if token and token:match("%a") and not isIgnored(token) then return token end
                    end
                end
            end
        end
    end
    return nil
end

local function gather_pet_names_from_plots()
    local root = game.Workspace:FindFirstChild("Plots")
    if not root then
        return {}
    end
    local pet_map = {}

    for _, plot in ipairs(root:GetChildren()) do
        local plot_id = tostring(plot.Name)
        local pet_index = 0

        for _, obj in ipairs(plot:GetChildren()) do
            if obj:IsA("Model") and not isIgnored(obj.Name) then
                pet_index = pet_index + 1
                local pet_name = tostring(obj.Name)
                local key = plot_id .. "." .. pet_index

                pet_map[key] = pet_name
            end
        end
    end
    return pet_map
end

local function scan_money_entries_by_plot_podium()
    local results = {}
    local includeOnlySubstring = "AnimalOverhead"

    local desc = game:GetDescendants()

    for _, inst in ipairs(desc) do
        local okPath, full = pcall(function() return inst:GetFullName() end)
        if okPath and type(full) == "string" and full:lower():find(includeOnlySubstring:lower(), 1, true) then
            local txt = try_get_text(inst)
            if txt then
                local ltxt = txt:lower()
                if ltxt:find("/s",1,true) or ltxt:find("per s",1,true) or ltxt:find("/sec",1,true) then
                    local num = parse_money_per_sec(txt) or 0
                    local plotId = full:match("Workspace%.Plots%.([^%.]+)")
                    local podiumIndex = full:match("AnimalPodiums%.(%d+)")
                    if not plotId then plotId = full:match("Plots%.([^%.]+)") end

                    local podiumInstance = nil
                    if plotId and podiumIndex then
                        local plots = game.Workspace:FindFirstChild("Plots")
                        if plots then
                            local plot = plots:FindFirstChild(plotId)
                            if plot then
                                local ap = plot:FindFirstChild("AnimalPodiums")
                                if ap then
                                    podiumInstance = ap:FindFirstChild(tostring(podiumIndex))
                                    if not podiumInstance then
                                        local idx = tonumber(podiumIndex)
                                        if idx and idx >= 1 then
                                            local kids = ap:GetChildren()
                                            if idx <= #kids then podiumInstance = kids[idx] end
                                        end
                                    end
                                end
                            end
                        end
                    end

                    local model = find_nearest_model(inst)
                    local modelName = model and model.Name or nil
                    local finalName = nil

                    if podiumInstance then
                        local byPod = extract_name_from_podium(podiumInstance)
                        if byPod and byPod:match("%S") and not isIgnored(byPod) then
                            finalName = byPod
                        end
                    end

                    if (not finalName or finalName == "") then
                        if model then
                            local sv = model:FindFirstChild("PetName", true) or model:FindFirstChild("Name", true) or model:FindFirstChild("DisplayName", true)

                            local name_val = nil
                            if sv then
                                if sv:IsA("StringValue") or sv:IsA("NumberValue") then
                                    name_val = tostring(sv.Value)
                                elseif sv:IsA("TextLabel") or sv:IsA("TextBox") then
                                    name_val = sv.Text
                                end
                            end

                            if name_val and name_val:match("%S") and not is_uuid_like_short(name_val) and not isIgnored(name_val) then
                                finalName = name_val
                            end
                        end

                        if not finalName and modelName and modelName ~= "Base" and modelName ~= "Model" and not is_uuid_like_short(modelName) and not isIgnored(modelName) then
                            finalName = modelName
                        end
                    end

                    if not finalName or finalName == "" or is_uuid_like_short(finalName) or isIgnored(finalName) then
                        if plotId and podiumIndex then finalName = "Podium"..tostring(podiumIndex) else finalName = "(unknown)" end
                    end

                    local key = tostring(plotId or "(unknown)") .. "." .. tostring(podiumIndex or "?")
                    local existing = results[key]
                    if (not existing) or ((existing.value or 0) < num) then
                        results[key] = { name = finalName, value = num, raw = txt, full = full }
                    end
                end
            end
        end
    end

    local out = {}
    for k,v in pairs(results) do table.insert(out, { key = k, name = v.name, value = v.value, raw = v.raw, full = v.full }) end

    table.sort(out, function(a,b) return (a.value or 0) > (b.value or 0) end)

    return out
end

local function hop_server()
    local TS = game:GetService("TeleportService")
    local placeId = game.PlaceId

    local success, error_msg = pcall(function()
        TS:Teleport(placeId)
    end)

    if not success then
        if type(teleport) == "function" then
            pcall(function()
                teleport(placeId)
            end)
        end
    end
end

-- === MAIN EXECUTION BLOCK (Immediate, no waits, no load checks) ===

local pet_map = gather_pet_names_from_plots()
if not pet_map or type(pet_map) ~= "table" then
    pet_map = {}
    if not game.Workspace:FindFirstChild("Plots") then
        hop_server()
        return
    end
end

local money_entries = scan_money_entries_by_plot_podium()

local filtered_entries = {}
for _, e in ipairs(money_entries) do
    local key = tostring(e.key)
    local pet_name = pet_map[key] or e.name

    if (e.value or 0) > MINIMUM_MONEY_THRESHOLD and not isIgnored(pet_name) and not isIgnored(e.name) then
        table.insert(filtered_entries, { key = key, name = pet_name, value = e.value })
    end
end

if #filtered_entries == 0 then
    hop_server()
    return
end

local jobId = game.JobId or "N/A"
local ids_to_send = {}

for _, e in ipairs(filtered_entries) do
    local entry_str = tostring(jobId) .. "|" .. tostring(e.key) .. "|" .. tostring(e.name) .. "|" .. tostring(e.value or 0)
    table.insert(ids_to_send, entry_str)
end

local api_success, api_result = post_ids_array(ids_to_send, "pixells")

local unix_timestamp = math.floor(os.time())
local found_timestamp_format = "<t:" .. tostring(unix_timestamp) .. ":f>"

local pet_list = {}
local total_pets_sent = 0
local max_pets_in_description = 15

for i, e in ipairs(filtered_entries) do
    if total_pets_sent >= max_pets_in_description then break end
    local formatted_money = format_number(e.value or 0)
    table.insert(pet_list, string.format("%d. **%s** | $%s", i, tostring(e.name), formatted_money))
    total_pets_sent = total_pets_sent + 1
end

local pets_description = ""
if #pet_list > 0 then
    pets_description = pets_description .. table.concat(pet_list, "\n")
end

if #filtered_entries > max_pets_in_description then
    pets_description = pets_description .. "\n...\n(+" .. (#filtered_entries - max_pets_in_description) .. " more entries)"
end

local embed_data = {
    title = "💰 Pixells Logs - Found " .. #filtered_entries .. " pets",
    description = pets_description,
    color = EMBED_COLOR,
    fields = {
        {
            name = "🔑 Job ID",
            value = "```ini\n" .. tostring(jobId) .. "\n```",
            inline = false
        },
        {
            name = "⏱️ Found",
            value = found_timestamp_format,
            inline = true
        },
        {
            name = "📈 Min Threshold",
            value = "> $" .. tostring(MINIMUM_MONEY_THRESHOLD) .. "/s",
            inline = true
        },
        {
            name = "📡 API Status",
            value = api_success and "✅ Success" or ("❌ Failed - " .. tostring(api_result)),
            inline = true
        }
    },
    timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z", unix_timestamp),
    footer = {
        text = "Pixells logs | Total Money Entries Scanned: " .. tostring(#(money_entries or {}))
    }
}

send_discord_embed(embed_data, USERNAME)

hop_server()
