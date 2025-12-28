local tattle = CreateFrame("Frame")

local TAUNTS = {
    "Taunt",
    "Mocking Blow",
    "Challenging Shout",
    "Growl",
    "Challenging Roar",
    "Hand of Reckoning",
    "Earthshaker Slam",
    "Righteous Defense",
}

local recentPulls = {}
local PULL_TIMEOUT = 30
local lastPullClean = 0
local CLEAN_INTERVAL = 15

-- Register Events
tattle:RegisterEvent("ADDON_LOADED")
tattle:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF") -- For casts on friendlies
tattle:RegisterEvent("CHAT_MSG_SPELL_PET_DAMAGE") -- Added for Pet Growl
tattle:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
tattle:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_PARTY_HITS")
tattle:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
tattle:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_PARTY_DAMAGE")

local function CheckTaunt(msg)
    if not msg then return nil end
    for i = 1, table.getn(TAUNTS) do
        if string.find(msg, TAUNTS[i]) then
            return TAUNTS[i]
        end
    end
    return nil
end

local function GetWho(msg)
    if string.find(msg, "^Your ") or string.find(msg, "^You ") then
        return UnitName("player")
    end
    -- Improved capture for names with spaces or pets (e.g., "Bob's Pet")
    local _, _, name = string.find(msg, "^(.+)'s ")
    if name then return name end
    
    _, _, name = string.find(msg, "^(.+) casts")
    return name
end

local function GetTarget(msg)
    -- Handle standard "cast on" (e.g., "You cast Taunt on Red Dragon.")
    local _, _, target = string.find(msg, " on (.+)%.")
    if target then return target end
    
    -- Handle damaging taunts (e.g., "Your Mocking Blow hits Red Dragon for...")
    -- Captures until " for" or " crits" to handle multi-word names
    _, _, target = string.find(msg, " hits (.+) for")
    if target then return target end
    
    _, _, target = string.find(msg, " crits (.+) for")
    if target then return target end

    -- Handle resists (e.g., "Your Taunt was resisted by Onyxia.")
    _, _, target = string.find(msg, " resisted by (.+)%.")
    if target then return target end
    
    return "unknown"
end

local function GetOutcome(msg)
    if string.find(msg, "resisted") then return "RESISTED" end
    if string.find(msg, "misses") then return "MISSED" end
    if string.find(msg, "dodged") then return "DODGED" end
    if string.find(msg, "parried") then return "PARRIED" end
    if string.find(msg, "blocked") then return "BLOCKED" end
    return "hit"
end

local function Announce(msg, prefix)
    prefix = prefix or "TauntTattle"
    if TAUNTTATTLE_SELF then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[" .. prefix .. "]|r " .. msg)
    elseif GetNumRaidMembers() > 0 then
        SendChatMessage("[" .. prefix .. "] " .. msg, "RAID")
    elseif GetNumPartyMembers() > 0 then
        SendChatMessage("[" .. prefix .. "] " .. msg, "PARTY")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[" .. prefix .. "]|r " .. msg)
    end
end

local function CleanOldPulls()
    local now = GetTime()
    for mob, time in pairs(recentPulls) do
        if (now - time) > PULL_TIMEOUT then
            recentPulls[mob] = nil
        end
    end
end

local function CheckPull(msg)
    if not TAUNTTATTLE_PULLS then return end
    if GetNumRaidMembers() == 0 then return end

    local _, _, mob, player = string.find(msg, "^(.+) hits (.+) for")
    if not mob then
        _, _, mob, player = string.find(msg, "^(.+) crits (.+) for")
    end
    if not mob then
        _, _, mob, player = string.find(msg, "^(.+)'s .+ hits (.+) for")
    end
    if not mob then
        _, _, mob, player = string.find(msg, "^(.+)'s .+ crits (.+) for")
    end

    if mob and player then
        -- Optimization: Only clean old pulls periodically
        local now = GetTime()
        if (now - lastPullClean) > CLEAN_INTERVAL then
            CleanOldPulls()
            lastPullClean = now
        end

        if not recentPulls[mob] then
            recentPulls[mob] = now
            Announce(player .. " pulled " .. mob, "Pull")
        end
    end
end

tattle:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "TauntTattle" then
        if TAUNTTATTLE_ENABLED == nil then TAUNTTATTLE_ENABLED = true end
        if TAUNTTATTLE_SELF == nil then TAUNTTATTLE_SELF = false end
        if TAUNTTATTLE_PULLS == nil then TAUNTTATTLE_PULLS = false end
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Loaded - /taunt for options")
        return
    end

    if not TAUNTTATTLE_ENABLED then return end

    local taunt = CheckTaunt(arg1)
    if taunt then
        local who = GetWho(arg1)
        local target = GetTarget(arg1)
        local outcome = GetOutcome(arg1)
        
        if who then
            if outcome ~= "hit" then
                Announce(who .. "'s " .. taunt .. " " .. outcome .. " on " .. target .. "!", "TauntFail")
            else
                Announce(who .. " used " .. taunt .. " on " .. target)
            end
        end
    end

    if string.find(event, "CREATURE_VS") then
        CheckPull(arg1)
    end
end)

SLASH_TAUNTTATTLE1 = "/taunttattle"
SLASH_TAUNTTATTLE2 = "/taunt"
SlashCmdList["TAUNTTATTLE"] = function(cmd)
    cmd = string.lower(cmd or "")
    if cmd == "self" then
        TAUNTTATTLE_SELF = not TAUNTTATTLE_SELF
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Self-only: " .. (TAUNTTATTLE_SELF and "On" or "Off"))
    elseif cmd == "pulls" then
        TAUNTTATTLE_PULLS = not TAUNTTATTLE_PULLS
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Pull detection (raid only): " .. (TAUNTTATTLE_PULLS and "On" or "Off"))
    elseif cmd == "on" then
        TAUNTTATTLE_ENABLED = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Enabled")
    elseif cmd == "off" then
        TAUNTTATTLE_ENABLED = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Disabled")
    elseif cmd == "status" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r Status:")
        DEFAULT_CHAT_FRAME:AddMessage("  Enabled: " .. (TAUNTTATTLE_ENABLED and "Yes" or "No"))
        DEFAULT_CHAT_FRAME:AddMessage("  Self-only: " .. (TAUNTTATTLE_SELF and "Yes" or "No"))
        DEFAULT_CHAT_FRAME:AddMessage("  Pulls (raid): " .. (TAUNTTATTLE_PULLS and "Yes" or "No"))
    else
        TAUNTTATTLE_ENABLED = not TAUNTTATTLE_ENABLED
        DEFAULT_CHAT_FRAME:AddMessage("|cffFF6600[TauntTattle]|r " .. (TAUNTTATTLE_ENABLED and "Enabled" or "Disabled"))
    end
end
