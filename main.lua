print("SCRIPT START OK")
-- Send_PetsAndMoney_ToWebhook.lua
-- Gathers pet data, sends a webhook if pets meet the threshold, then hops to a new server.

local WEBHOOK_URL = "https://discord.com/api/webhooks/1437468340783419623/utoeRw4LzXQHq6FzTFbbKHlw8R5O55fO25ASbMCS3UNA90qOPelCDbRJFU0YyZC23lrj"
local USERNAME = "Pixells Log"
local EMBED_COLOR = 0xFFFFFF 
local MINIMUM_MONEY_THRESHOLD = 10000000 -- CORRECTED to 10,000,000 ($10M)

-- === Name Filtering ===
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

-- === Webhook Helper Functions (Unchanged) ===
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
        table.insert(errors, "syn.request: " .. tostring(res))
    end
    if type(http) == "table" and type(http.request) == "function" then
        local ok, res = pcall(function() return http.request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "http.request: " .. tostring(res))
    end
    if type(request) == "function" then
        local ok, res = pcall(function() return request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "request: " .. tostring(res))
    end
    if type(http_request) == "function" then
        local ok, res = pcall(function() return http_request(req_table) end)
        if ok and res then return true, res end
        table.insert(errors, "http_request: " .. tostring(res))
    end
    return false, table.concat(errors, " | ")
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
        return false, "Executor HTTP Failure: " .. tostring(res_or_err)
    end
    
    if res_or_err.StatusCode >= 200 and res_or_err.StatusCode <= 299 then
        return true
    else
        local error_msg = string.format("Discord Status Code: %d. Response Body: %s", 
                                        res_or_err.StatusCode, 
                                        res_or_err.Body or "No body provided.")
        return false, error_msg
    end
end

-- === Utility Functions ===
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

-- FIX 3: Replaced parse_money_per_sec() for safer parsing
local function parse_money_per_sec(text)
    if type(text) ~= "string" then return nil end
    local s = text:lower()
    s = s:gsub("%s+", ""):gsub(",", ""):gsub("%$", "")
    s = s:gsub("/sec", ""):gsub("/s", ""):gsub("persec", ""):gsub("pers", ""):gsub("per", "")
    local numStr, suffix = s:match("([%+%-]?%d+%.?%d*)([tkmb]?)$")
    if not numStr then return nil end
    local n = tonumber(numStr)
    if not n then return nil end
    if suffix == "k" then n = n * 1e3
    elseif suffix == "m" then n = n * 1e6
    elseif suffix == "b" then n = n * 1e9
    elseif suffix == "t" then n = n * 1e12 end
    return n
end

-- FIX 4: Replaced try_get_text() to include TextButton
local function try_get_text(inst)
    local ok, v = pcall(function() return inst.Text end)
    if ok and type(v) == "string" and v ~= "" then
        if inst:IsA("TextLabel") or inst:IsA("TextBox") or inst:IsA("TextButton") then
            return v
        end
    end
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

-- Robust name extraction function (previously fixed logic)
local function extract_name_from_podium(podium)
    if not podium then return nil end
    
    local function try_get_property_value(obj, prop_name)
        if not obj then return nil end
        local ok, value = pcall(function()
            return obj[prop_name]
        end)
        return ok and value or nil
    end

    local function try_get_pet_name(obj)
        if not obj then return nil end
        
        local sv = obj:FindFirstChild("PetName", true) or obj:FindFirstChild("Name", true) or obj:FindFirstChild("DisplayName", true)
        if sv then
            if sv:IsA("StringValue") or sv:IsA("NumberValue") then
                local value = try_get_property_value(sv, "Value")
                if value then return tostring(value) end
            elseif sv:IsA("TextLabel") or sv:IsA("TextBox") then
                local text = try_get_property_value(sv, "Text")
                if text then return text end
            end
        end
        
        if obj:IsA("Model") and obj.Name and obj.Name ~= "Base" and obj.Name ~= "Model" and not is_uuid_like_short(obj.Name) and not isIgnored(obj.Name) then
            return obj.Name
        end
        return nil
    end

    for _, d in ipairs(podium:GetDescendants()) do
        local name_val = try_get_pet_name(d)
        if type(name_val) == "string" and name_val:match("%S") and not is_uuid_like_short(name_val) and not isIgnored(name_val) then
            return name_val
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

-- FIX 2: Changed first return value from nil to true
local function gather_pet_names_from_plots()
    local root = game.Workspace:FindFirstChild("Plots")
    if not root then
        return false, nil, "Plots not found in Workspace"
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
    return true, pet_map, nil -- <--- FIXED
end

-- FIX 5: Relaxed includeOnlySubstring
local function scan_money_entries_by_plot_podium()
    local results = {} 
    local includeOnlySubstring = "Animal" -- <--- FIXED (was "AnimalOverhead")
    
    local desc = game:GetDescendants()
    
    for _, inst in ipairs(desc) do
        local okPath, full = pcall(function() return inst:GetFullName() end)
        if not okPath or type(full) ~= "string" then
        else
            if not full:lower():find(includeOnlySubstring:lower(), 1, true) then
            else
                local txt = try_get_text(inst)
                if not txt then
                else
                    local ltxt = txt:lower()
                    if not (ltxt:find("/s",1,true) or ltxt:find("per s",1,true) or ltxt:find("/sec",1,true)) then
                    else
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
                        local finalName = nil

                        if podiumInstance then
                            local byPod = extract_name_from_podium(podiumInstance)
                            if byPod and byPod:match("%S") and not isIgnored(byPod) then
                                finalName = byPod
                            end
                        end

                        if (not finalName or finalName == "") and model then
                            local byModel = extract_name_from_podium(model)
                            if byModel and byModel:match("%S") and not isIgnored(byModel) then
                                finalName = byModel
                            end
                        end
                        
                        if not finalName and model and model.Name and model.Name ~= "Base" and model.Name ~= "Model" and not is_uuid_like_short(model.Name) and not isIgnored(model.Name) then
                            finalName = model.Name
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
    end

    local out = {}
    for k,v in pairs(results) do table.insert(out, { key = k, name = v.name, value = v.value, raw = v.raw, full = v.full }) end
    
    table.sort(out, function(a,b) return (a.value or 0) > (b.value or 0) end)
    
    return out
end

-- === SERVER HOPPING FUNCTION RE-ENABLED (Previously restored) ===
local function hop_server()
    local TS = game:GetService("TeleportService")
    local placeId = game.PlaceId
    
    print("Attempting server hop to new instance of PlaceID:", placeId)
    
    local success, error_msg = pcall(function()
        TS:Teleport(placeId)
    end)

    if not success then
        print("Teleport failed or is unsupported by executor:", error_msg or "Unknown error")
        if type(teleport) == "function" then
            pcall(function()
                teleport(placeId)
            end)
        end
    end
end

-- === MAIN EXECUTION BLOCK ===

print("Waiting for LocalPlayer to load and spawn character...")

local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

while not localPlayer do
    task.wait(0.1)
    localPlayer = Players.LocalPlayer
end

if not localPlayer.Character or not localPlayer.Character.Parent then
    localPlayer.CharacterAdded:Wait()
end

print("Character loaded. Waiting for game assets (game:IsLoaded()).")
if not game:IsLoaded() then
    if game.Loaded then
        game.Loaded:Wait()
    else
        while not game:IsLoaded() do 
            task.wait(0.1) 
        end
    end
end

wait(2) 
print("Game fully loaded. Starting server scan.")
-- FIX 6: DEBUG PRINT 1
print("DEBUG: Found Plots count:", (game.Workspace:FindFirstChild("Plots") and #game.Workspace.Plots:GetChildren()) or 0)
--------------------------------------------

local ok_pet, pet_map, pet_err = gather_pet_names_from_plots()
-- FIX 6: DEBUG PRINT 2
local map_count = 0 for _ in pairs(pet_map or {}) do map_count = map_count + 1 end
print("DEBUG: gather_pet_names_from_plots returned:", tostring(ok_pet), "pet_map size:", map_count, "err:", tostring(pet_err))

if not ok_pet and pet_err then
    pet_map = {}
    if not game.Workspace:FindFirstChild("Plots") then
        print("Error: 'Plots' folder still missing after full load. Skipping scan and hopping.")
        hop_server() -- Hop if essential folder is missing
        return
    end
end

local money_entries = scan_money_entries_by_plot_podium()
-- FIX 6: DEBUG PRINT 3
print("DEBUG: scanned money entries count:", tostring(#money_entries))
for i,v in ipairs(money_entries) do
    print(string.format("DEBUG ENTRY %d: key=%s name=%s raw=%s value=%s full=%s", i, tostring(v.key), tostring(v.name), tostring(v.raw), tostring(v.value), tostring(v.full)))
    if i>=10 then break end
end

local filtered_entries = {}
for _, e in ipairs(money_entries) do
    local key = tostring(e.key)
    local pet_name = pet_map[key] or e.name
    
    if (e.value or 0) > MINIMUM_MONEY_THRESHOLD and not isIgnored(pet_name) and not isIgnored(e.name) then
         table.insert(filtered_entries, { name = pet_name, value = e.value })
    end
end

if #filtered_entries == 0 then
    print("No pets found above the $" .. tostring(MINIMUM_MONEY_THRESHOLD) .. "/s threshold. Webhook skipped. Initiating server hop.")
    hop_server() -- Hop if no valuable pets are found
    return 
end

local jobId = game.JobId or "N/A"
local unix_timestamp = math.floor(os.time()) 
local found_timestamp_format = "<t:" .. tostring(unix_timestamp) .. ":f>" 

local pet_list = {}
local total_pets_sent = 0
local max_pets_in_description = 15 -- Limit the description length

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
            name = "🔑 **Job ID**",
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
        }
    },
    timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z", unix_timestamp),
    footer = {
        text = "Pixells-Logger | Total Money Entries Scanned: " .. #money_entries
    }
}

local ok, err = send_discord_embed(embed_data, USERNAME)

if not ok then
    print("🚨 Webhook FAILED:", err)
else
    print("✅ Webhook sent successfully. Filtered entries:", #filtered_entries)
end

hop_server() -- Hop after successful scan/webhook
