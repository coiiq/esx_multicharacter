local databaseReady = false
local databaseFailure = nil
local awaitingRegistration = {}
local selectionSessions = {}
local characterDeletionStatements = nil
local deletionLocks = {}
local eventCooldowns = {}

local function log(message)
    print(('[coii_multicharacter] %s'):format(message))
end

local function debugLog(message)
    if Config.Debug then log(message) end
end

local function isRateLimited(playerId, key, duration)
    local now = GetGameTimer()
    local cooldowns = eventCooldowns[playerId]
    if not cooldowns then
        cooldowns = {}
        eventCooldowns[playerId] = cooldowns
    end

    local previous = cooldowns[key]
    if previous and now - previous < duration then return true end
    cooldowns[key] = now
    return false
end

local function getIdentifier(playerId)
    local success, identifier = pcall(ESX.GetIdentifier, playerId)
    return success and identifier or nil
end

local function safeDecode(value, fallback)
    if type(value) ~= 'string' or value == '' then return fallback end
    local success, decoded = pcall(json.decode, value)
    return success and decoded or fallback
end

local function notify(playerId, message)
    TriggerClientEvent('coii_multicharacter:notify', playerId, message)
end

local function ensureDatabase()
    local ownershipTable = MySQL.query.await("SHOW TABLES LIKE 'coii_multicharacter_slots'")
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `coii_multicharacter_slots` (
            `identifier` VARCHAR(64) NOT NULL,
            `purchased_slots` TINYINT UNSIGNED NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `coii_multicharacter_preferences` (
            `identifier` VARCHAR(64) NOT NULL,
            `settings` LONGTEXT NOT NULL,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- One-time migration from the stock ESX per-player slot override table.
    if not ownershipTable or not ownershipTable[1] then
        local legacyTable = MySQL.query.await("SHOW TABLES LIKE 'multicharacter_slots'")
        if legacyTable and legacyTable[1] then
            local maximumPaid = math.max(0, Config.PaidSlots.TotalSlots - Config.PaidSlots.FreeSlots)
            MySQL.update.await([[
                INSERT INTO `coii_multicharacter_slots` (`identifier`, `purchased_slots`)
                SELECT `identifier`, LEAST(?, GREATEST(`slots` - ?, 0))
                FROM `multicharacter_slots`
                WHERE `slots` > ?
                ON DUPLICATE KEY UPDATE `purchased_slots` = GREATEST(`purchased_slots`, VALUES(`purchased_slots`))
            ]], { maximumPaid, Config.PaidSlots.FreeSlots, Config.PaidSlots.FreeSlots })
            log('Migrated stock ESX slot overrides')
        end
    end

    local lastPlayed = MySQL.query.await("SHOW COLUMNS FROM `users` LIKE 'last_played'")
    if not lastPlayed or not lastPlayed[1] then
        MySQL.query.await('ALTER TABLE `users` ADD COLUMN `last_played` DATETIME NULL DEFAULT NULL')
        log('Added users.last_played column')
    end

    local disabled = MySQL.query.await("SHOW COLUMNS FROM `users` LIKE 'disabled'")
    if not disabled or not disabled[1] then
        MySQL.query.await('ALTER TABLE `users` ADD COLUMN `disabled` TINYINT(1) NOT NULL DEFAULT 0')
        log('Added users.disabled column')
    end
end

MySQL.ready(function()
    if Config.AutoMigrate then
        local success, errorMessage = pcall(ensureDatabase)
        if not success then
            databaseFailure = tostring(errorMessage)
            log(('Database initialization failed: %s'):format(databaseFailure))
            return
        end
    end

    databaseReady = true
    log('Database ready')
end)

local function waitForDatabase(timeout)
    local deadline = GetGameTimer() + math.max(1000, tonumber(timeout) or 15000)
    while not databaseReady and not databaseFailure and GetGameTimer() < deadline do Wait(50) end
    return databaseReady
end

local function getPurchasedSlots(identifier)
    if not Config.PaidSlots.Enabled then return 0 end
    return tonumber(MySQL.scalar.await(
        'SELECT `purchased_slots` FROM `coii_multicharacter_slots` WHERE `identifier` = ?',
        { identifier }
    )) or 0
end

local function setPurchasedSlots(identifier, amount)
    local maximum = math.max(0, Config.PaidSlots.TotalSlots - Config.PaidSlots.FreeSlots)
    amount = math.max(0, math.min(maximum, math.floor(tonumber(amount) or 0)))
    MySQL.update.await([[
        INSERT INTO `coii_multicharacter_slots` (`identifier`, `purchased_slots`)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `purchased_slots` = VALUES(`purchased_slots`)
    ]], { identifier, amount })
    return amount
end

local function clampInteger(value, minimum, maximum, fallback)
    value = tonumber(value)
    if not value then return fallback end
    return math.max(minimum, math.min(maximum, math.floor(value + 0.5)))
end

local function validOptionId(collection, requested, fallback)
    for i = 1, #collection do
        if collection[i].id == requested then return requested end
    end
    return fallback
end

local function sanitizeHexColor(value, fallback)
    if type(value) ~= 'string' then return fallback end
    value = value:upper()
    if value:match('^#%x%x%x%x%x%x$') then return value end
    return fallback
end

local function sanitizePreferences(data)
    data = type(data) == 'table' and data or {}
    local defaults = Config.PreferenceDefaults
    local music = type(Config.Music) == 'table' and Config.Music or {}
    local musicTracks = type(music.Tracks) == 'table' and music.Tracks or {}
    local defaultMusicTrack = clampInteger(defaults.MusicTrack, 0, #musicTracks, 0)
    local validTheme = data.theme == 'light' or data.theme == 'dark' or data.theme == 'custom'
    local locale = IsSupportedLocale(data.locale) and data.locale or defaults.Locale
    if not IsSupportedLocale(locale) then locale = IsSupportedLocale(Config.Locale) and Config.Locale or 'en' end

    return {
        locale = locale,
        theme = validTheme and data.theme or defaults.Theme,
        customUiColor = sanitizeHexColor(data.customUiColor, defaults.CustomUiColor),
        customSettingsBackground = sanitizeHexColor(data.customSettingsBackground, defaults.CustomSettingsBackground),
        customSettingsText = sanitizeHexColor(data.customSettingsText, defaults.CustomSettingsText),
        track = clampInteger(data.track, 0, #musicTracks, defaultMusicTrack),
        volume = clampInteger(data.volume, 0, 100, defaults.MusicVolume),
        uiScale = clampInteger(data.uiScale, 85, 120, defaults.InterfaceScale),
        backgroundId = validOptionId(Config.Backgrounds, data.backgroundId, Config.Scene.DefaultBackground),
        animationId = validOptionId(Config.AnimationStyles, data.animationId, Config.Scene.DefaultAnimation),
        time = clampInteger(data.time, 0, 1439, Config.Scene.DefaultTime),
        weatherId = validOptionId(Config.WeatherPresets, data.weatherId, Config.Scene.DefaultWeather)
    }
end

local function getPreferences(identifier)
    local encoded = MySQL.scalar.await(
        'SELECT `settings` FROM `coii_multicharacter_preferences` WHERE `identifier` = ?',
        { identifier }
    )
    return sanitizePreferences(safeDecode(encoded, {}))
end

local function savePreferences(identifier, preferences)
    local sanitized = sanitizePreferences(preferences)
    MySQL.update.await([[
        INSERT INTO `coii_multicharacter_preferences` (`identifier`, `settings`)
        VALUES (?, ?)
        ON DUPLICATE KEY UPDATE `settings` = VALUES(`settings`)
    ]], { identifier, json.encode(sanitized) })
    return sanitized
end

local function getPlayerLocale(playerId)
    local session = selectionSessions[playerId]
    if session and IsSupportedLocale(session.locale) then return session.locale end
    return IsSupportedLocale(Config.Locale) and Config.Locale or 'en'
end

local function localizedForPlayer(playerId, key, replacements)
    return TranslateLocale(getPlayerLocale(playerId), key, replacements)
end

local function getJobLabel(jobName, gradeValue)
    local jobs = ESX.GetJobs()
    local job = jobs[jobName]
    local grade = job and job.grades[tostring(gradeValue)]
    if not job then return jobName or 'Unemployed', '' end
    return job.label or jobName, grade and grade.label or ''
end

local function getCharacters(identifier)
    local pattern = ('%s%%:%s'):format(Config.Prefix, identifier)
    local rows = MySQL.query.await([[
        SELECT `identifier`, `accounts`, `job`, `job_grade`, `firstname`, `lastname`,
               `dateofbirth`, `sex`, `skin`, `disabled`, `last_played`
        FROM `users`
        WHERE `identifier` LIKE ?
    ]], { pattern }) or {}

    local characters = {}
    local highestSlot = 0

    for i = 1, #rows do
        local row = rows[i]
        local slot = tonumber(row.identifier:match(('^%s(%%d+):'):format(Config.Prefix)))
        if slot then
            highestSlot = math.max(highestSlot, slot)
            local accounts = safeDecode(row.accounts, {})
            local jobLabel, gradeLabel = getJobLabel(row.job or 'unemployed', row.job_grade or 0)
            characters[#characters + 1] = {
                id = slot,
                slot = slot,
                firstname = row.firstname,
                lastname = row.lastname,
                dateofbirth = row.dateofbirth,
                sex = row.sex,
                jobName = row.job or 'unemployed',
                job = jobLabel,
                jobLabel = jobLabel,
                jobGrade = gradeLabel,
                jobGradeLabel = gradeLabel,
                bank = accounts.bank or 0,
                money = accounts.money or 0,
                skin = safeDecode(row.skin, {}),
                disabled = tonumber(row.disabled) == 1,
                lastPlayed = row.last_played
            }
        end
    end

    table.sort(characters, function(a, b) return a.slot < b.slot end)
    return characters, highestSlot
end

local function isValidStoreUrl(value)
    if type(value) ~= 'string' then return false end
    value = value:match('^%s*(.-)%s*$')
    return value:lower():match('^https?://') ~= nil
end

local function getSlotState(identifier, highestExistingSlot)
    local paid = Config.PaidSlots
    if not paid.Enabled then
        return {
            enabled = false,
            canDelete = Config.CanDelete == true,
            freeSlots = paid.TotalSlots,
            totalSlots = paid.TotalSlots,
            purchasedSlots = 0,
            unlockedSlots = paid.TotalSlots,
            priceLabel = paid.PriceLabel,
            storeEnabled = paid.StoreEnabled == true,
            storeUrl = isValidStoreUrl(paid.StoreUrl) and paid.StoreUrl or ''
        }
    end

    local purchased = getPurchasedSlots(identifier)
    if paid.GrandfatherExistingCharacters then
        local requiredPurchased = math.max(0, highestExistingSlot - paid.FreeSlots)
        if requiredPurchased > purchased then
            purchased = setPurchasedSlots(identifier, requiredPurchased)
            log(('Grandfathered %s with %s purchased slot(s)'):format(identifier, purchased))
        end
    end

    return {
        enabled = true,
        canDelete = Config.CanDelete == true,
        freeSlots = paid.FreeSlots,
        totalSlots = paid.TotalSlots,
        purchasedSlots = purchased,
        unlockedSlots = math.min(paid.TotalSlots, paid.FreeSlots + purchased),
        priceLabel = paid.PriceLabel,
        storeEnabled = paid.StoreEnabled == true,
        storeUrl = isValidStoreUrl(paid.StoreUrl) and paid.StoreUrl or ''
    }
end

local function sendCharacters(playerId, selectedIndex)
    if not waitForDatabase() then
        log(('Character request for player %s failed because the database is unavailable'):format(playerId))
        return DropPlayer(playerId, TranslateLocale(Config.Locale, 'database_unavailable'))
    end

    local identifier = getIdentifier(playerId)
    if not identifier then
        return DropPlayer(playerId, TranslateLocale(Config.Locale, 'identifier_resolution_failed'))
    end

    local success, payload = pcall(function()
        local characters, highestSlot = getCharacters(identifier)
        return {
            characters = characters,
            slotState = getSlotState(identifier, highestSlot),
            preferences = getPreferences(identifier)
        }
    end)

    if not success then
        log(('Failed to load characters for player %s: %s'):format(playerId, tostring(payload)))
        return DropPlayer(playerId, TranslateLocale(Config.Locale, 'database_unavailable'))
    end

    SetPlayerRoutingBucket(playerId, playerId)
    ESX.Players[identifier] = playerId
    selectionSessions[playerId] = {
        identifier = identifier,
        unlockedSlots = payload.slotState.unlockedSlots,
        locale = payload.preferences.locale,
        busy = false
    }
    local initialSlot = tonumber(selectedIndex)
        or (payload.characters[1] and payload.characters[1].slot)
        or 1

    TriggerClientEvent('coii_multicharacter:open', playerId, payload.characters, payload.slotState,
        initialSlot, payload.preferences)
end

local function characterMap(characters)
    local mapped = {}
    for i = 1, #characters do mapped[characters[i].slot] = characters[i] end
    return mapped
end

local function rejectSelection(playerId, key, replacements)
    notify(playerId, localizedForPlayer(playerId, key, replacements))
    sendCharacters(playerId)
end

RegisterNetEvent('coii_multicharacter:requestCharacters', function()
    local playerId = source
    if ESX.GetPlayerFromId(playerId) then return end
    if isRateLimited(playerId, 'characters', 750) then return end
    local session = selectionSessions[playerId]
    if session and session.busy then return end
    sendCharacters(playerId)
end)

RegisterNetEvent('coii_multicharacter:savePreferences', function(preferences)
    local playerId = source
    if isRateLimited(playerId, 'preferences', 250) then return end
    local session = selectionSessions[playerId]
    local identifier = getIdentifier(playerId)
    if not session or not identifier or session.identifier ~= identifier then return end

    if not waitForDatabase() then return end
    local success, sanitized = pcall(savePreferences, identifier, preferences)
    if not success then
        return log(('Failed to save preferences for %s: %s'):format(identifier, tostring(sanitized)))
    end
    if session then session.locale = sanitized.locale end
    debugLog(('Saved interface preferences for %s'):format(identifier))
end)

RegisterNetEvent('coii_multicharacter:chooseCharacter', function(slot, isNew)
    local playerId = source
    slot = tonumber(slot)
    if not slot or slot % 1 ~= 0 or type(isNew) ~= 'boolean' then return end
    if slot < 1 or slot > Config.PaidSlots.TotalSlots then return end

    local identifier = getIdentifier(playerId)
    local session = selectionSessions[playerId]
    if not identifier or not session or session.identifier ~= identifier or session.busy then return end
    session.busy = true

    local success, payload = pcall(function()
        local characters, highestSlot = getCharacters(identifier)
        return {
            slots = getSlotState(identifier, highestSlot),
            existing = characterMap(characters)[slot]
        }
    end)

    if not success then
        session.busy = false
        log(('Failed to validate character selection for player %s: %s'):format(playerId, tostring(payload)))
        return TriggerClientEvent('coii_multicharacter:selectionFailed', playerId,
            localizedForPlayer(playerId, 'selection_request_failed'))
    end

    if slot > payload.slots.unlockedSlots then
        return rejectSelection(playerId, 'slot_locked')
    end

    if isNew then
        if payload.existing then return rejectSelection(playerId, 'slot_occupied') end
        awaitingRegistration[playerId] = {
            slot = slot,
            identifier = identifier,
            locale = session.locale
        }
        selectionSessions[playerId] = nil
        TriggerClientEvent('coii_multicharacter:beginRegistration', playerId, slot)
        return
    end

    if not payload.existing then return rejectSelection(playerId, 'character_not_found') end
    if payload.existing.disabled then return rejectSelection(playerId, 'character_disabled_sentence') end

    local characterIdentifier = ('%s%s'):format(Config.Prefix, slot)
    local fullIdentifier = ('%s:%s'):format(characterIdentifier, identifier)
    if ESX.GetPlayerFromIdentifier(fullIdentifier) then
        return DropPlayer(playerId, localizedForPlayer(playerId, 'character_already_active'))
    end

    selectionSessions[playerId] = nil
    SetPlayerRoutingBucket(playerId, 0)
    MySQL.update('UPDATE `users` SET `last_played` = CURRENT_TIMESTAMP WHERE `identifier` = ?', { fullIdentifier })
    ESX.Players[identifier] = characterIdentifier
    TriggerClientEvent('coii_multicharacter:selectionAccepted', playerId)
    TriggerEvent('esx:onPlayerJoined', playerId, characterIdentifier)
end)

local function sendDeleteStatus(playerId, success, key, replacements)
    TriggerClientEvent('coii_multicharacter:deleteStatus', playerId, success == true,
        localizedForPlayer(playerId, key, replacements))
end

local function getCharacterDeletionStatements()
    if characterDeletionStatements then return characterDeletionStatements end

    local columns = MySQL.query.await([[
        SELECT C.`TABLE_NAME`, C.`COLUMN_NAME`
        FROM `INFORMATION_SCHEMA`.`COLUMNS` C
        INNER JOIN `INFORMATION_SCHEMA`.`TABLES` T
          ON T.`TABLE_SCHEMA` = C.`TABLE_SCHEMA`
         AND T.`TABLE_NAME` = C.`TABLE_NAME`
        WHERE C.`TABLE_SCHEMA` = DATABASE()
          AND T.`TABLE_TYPE` = 'BASE TABLE'
          AND C.`DATA_TYPE` = 'varchar'
          AND C.`COLUMN_NAME` IN ('identifier', 'owner')
    ]]) or {}
    local statements = {}
    local userStatements = {}
    local seen = {}

    for i = 1, #columns do
        local tableName = tostring(columns[i].TABLE_NAME or '')
        local columnName = tostring(columns[i].COLUMN_NAME or '')
        local key = tableName .. ':' .. columnName

        if tableName ~= '' and columnName ~= '' and not seen[key] then
            seen[key] = true
            local isUsersTable = tableName == 'users'
            tableName = tableName:gsub('`', '``')
            columnName = columnName:gsub('`', '``')
            local statement = ('DELETE FROM `%s` WHERE `%s` = ?'):format(tableName, columnName)
            local destination = isUsersTable and userStatements or statements
            destination[#destination + 1] = statement
        end
    end

    for i = 1, #userStatements do statements[#statements + 1] = userStatements[i] end

    characterDeletionStatements = statements
    debugLog(('Cached %s character deletion statement(s)'):format(#characterDeletionStatements))
    return characterDeletionStatements
end

local function getCharacterDeletionQueries(fullIdentifier)
    local statements = getCharacterDeletionStatements()
    local queries = {}

    for i = 1, #statements do
        queries[i] = {
            query = statements[i],
            values = { fullIdentifier }
        }
    end

    return queries
end

RegisterNetEvent('coii_multicharacter:deleteCharacter', function(slot)
    local playerId = source
    slot = tonumber(slot)

    if not Config.CanDelete then
        return sendDeleteStatus(playerId, false, 'deletion_disabled')
    end
    if not slot or slot % 1 ~= 0 or slot < 1 or slot > Config.PaidSlots.TotalSlots then
        return sendDeleteStatus(playerId, false, 'invalid_character_slot')
    end

    local session = selectionSessions[playerId]
    local identifier = getIdentifier(playerId)
    if not session or not identifier or session.identifier ~= identifier then
        return sendDeleteStatus(playerId, false, 'invalid_character_session')
    end
    if deletionLocks[playerId] then
        return sendDeleteStatus(playerId, false, 'deletion_in_progress')
    end

    if not waitForDatabase() then return sendDeleteStatus(playerId, false, 'database_unavailable') end
    deletionLocks[playerId] = true

    local operationSuccess, result = pcall(function()
        local characters = getCharacters(identifier)
        local existing = characterMap(characters)[slot]
        if not existing then return { error = 'character_not_found' } end
        if existing.disabled then return { error = 'disabled_delete_forbidden' } end

        local fullIdentifier = ('%s%s:%s'):format(Config.Prefix, slot, identifier)
        if ESX.GetPlayerFromIdentifier(fullIdentifier) then
            return { error = 'active_delete_forbidden' }
        end

        local queries = getCharacterDeletionQueries(fullIdentifier)
        if #queries == 0 then return { error = 'deletion_tables_missing' } end
        if not MySQL.transaction.await(queries) then return { error = 'character_deletion_failed' } end

        return { fullIdentifier = fullIdentifier }
    end)

    deletionLocks[playerId] = nil
    if not operationSuccess then
        log(('Character deletion crashed for player %s: %s'):format(playerId, tostring(result)))
        return sendDeleteStatus(playerId, false, 'character_deletion_failed')
    end
    if result.error then
        return sendDeleteStatus(playerId, false, result.error)
    end

    log(('Player %s deleted character %s'):format(playerId, result.fullIdentifier))
    TriggerEvent('coii_multicharacter:characterDeleted', playerId, result.fullIdentifier, slot)
    sendDeleteStatus(playerId, true, 'character_deleted')
    sendCharacters(playerId, slot)
end)

AddEventHandler('esx_identity:completedRegistration', function(playerId, data)
    local pending = awaitingRegistration[playerId]
    if not pending or type(data) ~= 'table' then return end

    awaitingRegistration[playerId] = nil
    local identifier = getIdentifier(playerId)
    if not identifier or identifier ~= pending.identifier then
        return DropPlayer(playerId, TranslateLocale(Config.Locale, 'identifier_resolution_failed'))
    end

    local success, isAllowed = pcall(function()
        local characters, highestSlot = getCharacters(identifier)
        local slots = getSlotState(identifier, highestSlot)
        return pending.slot <= slots.unlockedSlots and characterMap(characters)[pending.slot] == nil
    end)

    if not success then
        log(('Failed to validate registration for player %s: %s'):format(playerId, tostring(isAllowed)))
        return DropPlayer(playerId, TranslateLocale(pending.locale or Config.Locale, 'database_unavailable'))
    end
    if not isAllowed then
        notify(playerId, TranslateLocale(pending.locale or Config.Locale, 'slot_occupied'))
        return sendCharacters(playerId, pending.slot)
    end

    local characterIdentifier = ('%s%s'):format(Config.Prefix, pending.slot)
    ESX.Players[pending.identifier] = characterIdentifier
    SetPlayerRoutingBucket(playerId, 0)
    TriggerEvent('esx:onPlayerJoined', playerId, characterIdentifier, data)
end)

RegisterNetEvent('coii_multicharacter:requestPurchase', function(slot)
    local playerId = source
    if isRateLimited(playerId, 'purchase', 1000) then return end
    slot = tonumber(slot)
    if not Config.PaidSlots.Enabled
        or not slot
        or slot % 1 ~= 0
        or slot < 1
        or slot > Config.PaidSlots.TotalSlots then return end

    local identifier = getIdentifier(playerId)
    local session = selectionSessions[playerId]
    if not identifier or not session or session.identifier ~= identifier then return end

    local success, state = pcall(function()
        local _, highestSlot = getCharacters(identifier)
        return getSlotState(identifier, highestSlot)
    end)
    if not success then
        log(('Failed to validate slot purchase for player %s: %s'):format(playerId, tostring(state)))
        return TriggerClientEvent('coii_multicharacter:purchaseStatus', playerId, false,
            localizedForPlayer(playerId, 'database_unavailable'))
    end
    if slot <= state.unlockedSlots then
        return TriggerClientEvent('coii_multicharacter:purchaseStatus', playerId, false,
            localizedForPlayer(playerId, 'slot_already_unlocked'))
    end
    if not Config.PaidSlots.StoreEnabled then
        return TriggerClientEvent('coii_multicharacter:purchaseStatus', playerId, false,
            localizedForPlayer(playerId, 'store_not_enabled'))
    end
    if not isValidStoreUrl(Config.PaidSlots.StoreUrl) then
        return TriggerClientEvent('coii_multicharacter:purchaseStatus', playerId, false,
            localizedForPlayer(playerId, 'store_url_not_configured'))
    end

    TriggerEvent('coii_multicharacter:purchaseRequested', playerId, identifier, slot)
    TriggerClientEvent('coii_multicharacter:purchaseStatus', playerId, true,
        localizedForPlayer(playerId, 'opening_store'))
end)

local function resolveIdentifier(value)
    local playerId = tonumber(value)
    if playerId and GetPlayerName(playerId) then return getIdentifier(playerId), playerId end
    if type(value) == 'string' and value:find(':', 1, true) then return value, nil end
end

local function changePaidSlots(value, delta)
    if not waitForDatabase() then
        return false, TranslateLocale(Config.Locale, 'database_unavailable')
    end
    local identifier, playerId = resolveIdentifier(value)
    if not identifier then return false, TranslateLocale(Config.Locale, 'player_identifier_not_found') end

    local success, updated = pcall(function()
        local current = getPurchasedSlots(identifier)
        return setPurchasedSlots(identifier, current + delta)
    end)
    if not success then
        log(('Failed to update paid slots for %s: %s'):format(identifier, tostring(updated)))
        return false, TranslateLocale(Config.Locale, 'database_unavailable')
    end
    if playerId and selectionSessions[playerId] then sendCharacters(playerId) end
    return true, TranslateLocale(Config.Locale, 'paid_slots_updated', {
        identifier = identifier,
        amount = updated
    })
end

local function isAdmin(playerId)
    if playerId == 0 then return true end
    if IsPlayerAceAllowed(playerId, Config.Commands.AcePermission) then return true end
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup()
    return group == 'admin' or group == 'superadmin'
end

local function commandReply(playerId, message)
    if playerId == 0 then return log(message) end
    notify(playerId, message)
end

RegisterCommand(Config.Commands.GrantSlot, function(playerId, args)
    if not isAdmin(playerId) then return commandReply(playerId, localizedForPlayer(playerId, 'no_permission')) end
    local ok, message = changePaidSlots(args[1], math.max(1, tonumber(args[2]) or 1))
    commandReply(playerId, message)
end, false)

RegisterCommand(Config.Commands.RevokeSlot, function(playerId, args)
    if not isAdmin(playerId) then return commandReply(playerId, localizedForPlayer(playerId, 'no_permission')) end
    local ok, message = changePaidSlots(args[1], -math.max(1, tonumber(args[2]) or 1))
    commandReply(playerId, message)
end, false)

exports('GrantPaidSlots', function(identifierOrSource, amount)
    return changePaidSlots(identifierOrSource, math.max(1, tonumber(amount) or 1))
end)

exports('RevokePaidSlots', function(identifierOrSource, amount)
    return changePaidSlots(identifierOrSource, -math.max(1, tonumber(amount) or 1))
end)

RegisterNetEvent('coii_multicharacter:relog', function()
    if not Config.Relog then return end
    local playerId = source
    if ESX.GetPlayerFromId(playerId) then TriggerEvent('esx:playerLogout', playerId) end
end)

AddEventHandler('esx:playerDropped', function(playerId)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    if xPlayer and xPlayer.identifier then
        MySQL.update('UPDATE `users` SET `last_played` = CURRENT_TIMESTAMP WHERE `identifier` = ?', { xPlayer.identifier })
    end
end)

AddEventHandler('playerDropped', function()
    local playerId = source
    local identifier = getIdentifier(playerId)
    awaitingRegistration[playerId] = nil
    selectionSessions[playerId] = nil
    deletionLocks[playerId] = nil
    eventCooldowns[playerId] = nil
    if identifier then ESX.Players[identifier] = nil end
end)

AddEventHandler('playerConnecting', function(_, _, deferrals)
    local playerId = source
    deferrals.defer()
    Wait(0)
    deferrals.update('Waiting for the character database...')
    if not waitForDatabase() then
        return deferrals.done(TranslateLocale(Config.Locale, 'database_unavailable'))
    end

    local identifier = getIdentifier(playerId)
    if not identifier then return deferrals.done('Unable to retrieve your ESX identifier.') end

    local active = ESX.Players[identifier]
    if type(active) == 'number' and active ~= playerId and GetPlayerPing(active) > 0 then
        return deferrals.done(('Your identifier is already connected: %s'):format(identifier))
    end

    ESX.Players[identifier] = playerId
    deferrals.done()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if resourceName ~= Config.RequiredResourceName then
        log(('WARNING: install this resource as "%s". ESX will not enable multicharacter mode under "%s".')
            :format(Config.RequiredResourceName, resourceName))
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for playerId, session in pairs(selectionSessions) do
        if GetPlayerName(playerId) then SetPlayerRoutingBucket(playerId, 0) end
        if session.identifier and ESX.Players[session.identifier] == playerId then
            ESX.Players[session.identifier] = nil
        end
    end

    for playerId, pending in pairs(awaitingRegistration) do
        if GetPlayerName(playerId) then SetPlayerRoutingBucket(playerId, 0) end
        if pending.identifier and ESX.Players[pending.identifier] == playerId then
            ESX.Players[pending.identifier] = nil
        end
    end

    awaitingRegistration = {}
    selectionSessions = {}
    deletionLocks = {}
    eventCooldowns = {}
end)
