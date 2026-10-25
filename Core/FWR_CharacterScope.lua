local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local function normalizeText(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "" then
        return nil
    end

    return value
end

function FWR:GetCurrentCharacterIdentity()
    local characterName = nil
    local realmName = nil

    if type(UnitFullName) == "function" then
        local resolvedCharacterName, resolvedRealmName = UnitFullName("player")
        characterName = normalizeText(resolvedCharacterName)
        realmName = normalizeText(resolvedRealmName)
    end

    if not characterName and type(UnitName) == "function" then
        local resolvedCharacterName, resolvedRealmName = UnitName("player")
        characterName = normalizeText(resolvedCharacterName)
        realmName = realmName or normalizeText(resolvedRealmName)
    end

    return characterName, realmName
end

function FWR:BuildCharacterKey(characterName, realmName)
    characterName = normalizeText(characterName) or ""
    realmName = normalizeText(realmName)

    if characterName == "" then
        return ""
    end

    if realmName and realmName ~= "" then
        return characterName .. "-" .. realmName
    end

    return characterName
end

function FWR:GetCurrentCharacterKey()
    local characterName, realmName = self:GetCurrentCharacterIdentity()
    return self:BuildCharacterKey(characterName, realmName), characterName, realmName
end

function FWR:BuildCharacterScopedContextKey(baseContextKey, characterKey)
    local resolvedContextKey = normalizeText(baseContextKey) or ""
    local resolvedCharacterKey = normalizeText(characterKey) or ""

    if resolvedContextKey == "" and resolvedCharacterKey == "" then
        return "__global"
    end

    if resolvedContextKey == "" then
        return "character::" .. resolvedCharacterKey
    end

    if resolvedCharacterKey == "" then
        return resolvedContextKey
    end

    return resolvedContextKey .. "##" .. resolvedCharacterKey
end
