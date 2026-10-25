local FWR = FarmWiseReforged or {}
FarmWiseReforged = FWR

local function buildEmptyDatabase(now, dbVersion, buildName)
    return {
        meta = {
            dbVersion = dbVersion,
            build = buildName,
            createdAt = now,
            updatedAt = now,
            resets = 0,
        },

        goldLedger = {
            byContextKey = {},
        },

        renderState = {
            displayBasketByContext = {},
            currentContextKey = "__global",
            displayBasket = {
                order = {},
                byKey = {},
            },
        },
    }
end

local function buildEmptySettings()
    return {}
end


local function normalizeDisplayBasketAliases(renderState)
    renderState = type(renderState) == "table" and renderState or {}

    local displayBasket = type(renderState.displayBasket) == "table" and renderState.displayBasket or nil
    local legacyDisplayBasket = type(renderState.legacyDisplayBasket) == "table" and renderState.legacyDisplayBasket or nil
    local debugDisplayBasketAlias = type(renderState.debugAggregate) == "table" and renderState.debugAggregate or nil

    if not displayBasket then
        displayBasket = legacyDisplayBasket or debugDisplayBasketAlias
    end

    if not displayBasket then
        displayBasket = { order = {}, byKey = {} }
    end

    displayBasket.order = displayBasket.order or {}
    displayBasket.byKey = displayBasket.byKey or {}
    renderState.displayBasket = displayBasket
    return displayBasket
end

local function normalizeDisplayFilterAliases(settings, defaults)
    settings = type(settings) == "table" and settings or {}

    local displayFilters = type(settings.displayFilters) == "table" and settings.displayFilters or nil
    local legacyDisplayFilters = type(settings.legacyDisplayFilters) == "table" and settings.legacyDisplayFilters or nil
    local debugDisplayFilterAlias = type(settings.debugRender) == "table" and settings.debugRender or nil

    if not displayFilters then
        displayFilters = legacyDisplayFilters or debugDisplayFilterAlias
    end

    if not displayFilters then
        displayFilters = FWR:DeepCopy((defaults and defaults.displayFilters) or {})
    end

    settings.displayFilters = displayFilters or {}
    return settings.displayFilters
end

function FWR:EnsureDatabases()
    -- called many times a frame: once the databases are set up there is nothing left to do
    if self.__fwrDatabasesReady and self.DB == FarmWiseReforgedDB and self.Settings == FarmWiseReforgedSettingsDB then
        return self.DB, self.Settings
    end

    local now = self:Now()

    if type(FarmWiseReforgedDB) ~= "table" then
        FarmWiseReforgedDB = buildEmptyDatabase(now, self.DB_VERSION, self.BUILD_NAME)
    end

    if type(FarmWiseReforgedSettingsDB) ~= "table" then
        FarmWiseReforgedSettingsDB = buildEmptySettings()
    end

    FarmWiseReforgedDB.meta = FarmWiseReforgedDB.meta or {}
    FarmWiseReforgedDB.meta.dbVersion = self.DB_VERSION
    FarmWiseReforgedDB.meta.build = self.BUILD_NAME
    FarmWiseReforgedDB.meta.createdAt = FarmWiseReforgedDB.meta.createdAt or now
    FarmWiseReforgedDB.meta.updatedAt = now
    FarmWiseReforgedDB.meta.resets = tonumber(FarmWiseReforgedDB.meta.resets) or 0

    FarmWiseReforgedDB.goldLedger = FarmWiseReforgedDB.goldLedger or { byContextKey = {} }
    FarmWiseReforgedDB.goldLedger.byContextKey = FarmWiseReforgedDB.goldLedger.byContextKey or {}
    FarmWiseReforgedDB.renderState = FarmWiseReforgedDB.renderState or {}
    FarmWiseReforgedDB.renderState.displayBasketByContext = FarmWiseReforgedDB.renderState.displayBasketByContext or {}
    FarmWiseReforgedDB.renderState.currentContextKey = FarmWiseReforgedDB.renderState.currentContextKey or "__global"

    normalizeDisplayBasketAliases(FarmWiseReforgedDB.renderState)

    FarmWiseReforgedSettingsDB = FWR:MergeDefaults(FarmWiseReforgedSettingsDB, FWR.DEFAULT_SETTINGS)

    normalizeDisplayFilterAliases(FarmWiseReforgedSettingsDB, FWR.DEFAULT_SETTINGS)

    self.DB = FarmWiseReforgedDB
    self.Settings = FarmWiseReforgedSettingsDB
    self.__fwrDatabasesReady = true
    return self.DB, self.Settings
end

function FWR:TouchDatabase()
    if self.DB and self.DB.meta then
        self.DB.meta.updatedAt = self:Now()
    end
end

function FWR:ClearAllSavedData()
    local now = self:Now()
    local previousResets = tonumber(FarmWiseReforgedDB and FarmWiseReforgedDB.meta and FarmWiseReforgedDB.meta.resets) or 0

    FarmWiseReforgedDB = buildEmptyDatabase(now, self.DB_VERSION, self.BUILD_NAME)
    FarmWiseReforgedDB.meta.resets = previousResets + 1
    FarmWiseReforgedDB.meta.updatedAt = now

    self.DB = FarmWiseReforgedDB

    self:Emit("dataCleared")

    -- the new database has no current zone yet; without it no time or gold is credited
    if self.RefreshIdleZoneInfo then
        self:RefreshIdleZoneInfo()
    end

    if self.TouchDatabase then
        self:TouchDatabase()
    end

    if self.ApplyDisplaySettings then
        self:ApplyDisplaySettings()
    elseif self.RefreshDisplayText then
        self:RefreshDisplayText()
    end

    if self.RefreshMainWindowText then
        self:RefreshMainWindowText()
    end

    if self.RefreshDisplayLiveMetrics then
        self:RefreshDisplayLiveMetrics(true)
    end

    return self.DB
end
