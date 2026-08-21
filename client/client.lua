local state = {
    active = false,
    nuiReady = false,
    nuiOpen = false,
    spawnedPreview = false,
    characters = {},
    characterList = {},
    selectedSlot = 1,
    canRelog = true,
    transitionBusy = false,
    selectionLocked = false,
    selectionRequestRevision = 0,
    characterTransitionRevision = 0,
    sceneRevision = 0,
    focusRackRevision = 0,
    preferences = nil
}

local recoverSelection

local function findById(collection, id)
    for i = 1, #collection do
        if collection[i].id == id then return collection[i], i end
    end
    return collection[1], 1
end

local function defaultScenePreferences()
    return {
        backgroundId = Config.Scene.DefaultBackground,
        animationId = Config.Scene.DefaultAnimation,
        time = Config.Scene.DefaultTime,
        weatherId = Config.Scene.DefaultWeather
    }
end

state.scenePreferences = defaultScenePreferences()
state.background = findById(Config.Backgrounds, state.scenePreferences.backgroundId)
state.animation = findById(Config.AnimationStyles, state.scenePreferences.animationId)

local function localizedText(key, replacements)
    local locale = state.preferences and state.preferences.locale or Config.Locale
    return TranslateLocale(locale, key, replacements)
end

local function notify(message)
    if state.nuiOpen then
        SendNUIMessage({ action = 'notify', message = message })
    else
        ESX.ShowNotification(message)
    end
end

local function awaitFadeOut()
    while IsScreenFadingOut() do Wait(50) end
end

local function awaitFadeIn()
    while IsScreenFadingIn() do Wait(50) end
end

local function setHudHidden(hidden)
    DisplayRadar(not hidden)
    DisplayHud(not hidden)
    if MumbleSetVolumeOverride then
        MumbleSetVolumeOverride(PlayerId(), hidden and 0.0 or -1.0)
    end
end

local function sceneOffset(offset)
    local coords = state.background.coords
    return GetOffsetFromCoordAndHeadingInWorldCoords(
        coords.x, coords.y, coords.z, coords.w,
        offset.x, offset.y, offset.z
    )
end

local function applyEnvironment()
    local minutes = math.max(0, math.min(1439, tonumber(state.scenePreferences.time) or Config.Scene.DefaultTime))
    local weather = findById(Config.WeatherPresets, state.scenePreferences.weatherId)
    state.scenePreferences.weatherId = weather.id

    if Config.Scene.TimeSettingsEnabled ~= false then
        NetworkOverrideClockTime(math.floor(minutes / 60), minutes % 60, 0)
    end

    if Config.Scene.WeatherSettingsEnabled ~= false then
        SetWeatherTypePersist(weather.id)
        SetWeatherTypeNow(weather.id)
        SetWeatherTypeNowPersist(weather.id)
    end
end

local function clearEnvironment()
    if Config.Scene.TimeSettingsEnabled ~= false then
        NetworkClearClockTimeOverride()
    end

    if Config.Scene.WeatherSettingsEnabled ~= false then
        ClearOverrideWeather()
        ClearWeatherTypePersist()
    end
end

local function destroyCamera()
    state.focusRackRevision = state.focusRackRevision + 1
    if not state.camera then return end
    SetCamUseShallowDofMode(state.camera, false)
    SetCamActive(state.camera, false)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(state.camera, false)
    state.camera = nil
end

local function setupCamera()
    destroyCamera()
    local cameraPosition = sceneOffset(Config.Scene.CameraOffset)
    local lookAt = sceneOffset(Config.Scene.CameraLookAt)

    state.camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(state.camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(state.camera, lookAt.x, lookAt.y, lookAt.z)
    SetCamActive(state.camera, true)
    SetCamFov(state.camera, 38.0)

    local depthOfField = Config.Scene.DepthOfField
    if depthOfField and depthOfField.Enabled then
        SetCamUseShallowDofMode(state.camera, true)
        SetCamNearDof(state.camera, tonumber(depthOfField.NearDof) or 2.0)
        SetCamFarDof(state.camera, tonumber(depthOfField.FarDof) or 5.5)
        SetCamDofStrength(state.camera, tonumber(depthOfField.Strength) or 1.0)
    end

    RenderScriptCams(true, false, 0, true, true)
end

local function setCameraDepthOfField(nearDof, farDof, strength)
    if not state.camera then return end
    SetCamUseShallowDofMode(state.camera, true)
    SetCamNearDof(state.camera, nearDof)
    SetCamFarDof(state.camera, farDof)
    SetCamDofStrength(state.camera, strength)
end

local function restoreCameraDepthOfField()
    local depthOfField = Config.Scene.DepthOfField
    if not state.camera or not depthOfField or not depthOfField.Enabled then return end
    setCameraDepthOfField(
        tonumber(depthOfField.NearDof) or 2.0,
        tonumber(depthOfField.FarDof) or 5.5,
        tonumber(depthOfField.Strength) or 1.0
    )
end

local function startFocusRack()
    local focusRack = type(Config.Scene.FocusRack) == 'table' and Config.Scene.FocusRack or nil
    local depthOfField = Config.Scene.DepthOfField
    if not state.camera
        or not state.nuiOpen
        or not focusRack
        or not focusRack.Enabled
        or not depthOfField
        or not depthOfField.Enabled then return end

    state.focusRackRevision = state.focusRackRevision + 1
    local revision = state.focusRackRevision
    local camera = state.camera
    local normalNear = tonumber(depthOfField.NearDof) or 2.0
    local normalFar = tonumber(depthOfField.FarDof) or 5.5
    local normalStrength = tonumber(depthOfField.Strength) or 1.0
    local blurNear = tonumber(focusRack.BlurNearDof) or 0.25
    local blurFar = tonumber(focusRack.BlurFarDof) or 1.15
    local blurStrength = tonumber(focusRack.BlurStrength) or 1.0

    local function isValid()
        return state.active
            and state.camera == camera
            and state.focusRackRevision == revision
    end

    local function animateDepthOfField(fromNear, fromFar, fromStrength, toNear, toFar, toStrength, duration)
        local startedAt = GetGameTimer()
        duration = math.max(1, tonumber(duration) or 1)

        while isValid() do
            if state.selectionLocked then
                restoreCameraDepthOfField()
                return false
            end

            local progress = math.min(1.0, (GetGameTimer() - startedAt) / duration)
            local eased = progress * progress * (3.0 - (2.0 * progress))
            setCameraDepthOfField(
                fromNear + ((toNear - fromNear) * eased),
                fromFar + ((toFar - fromFar) * eased),
                fromStrength + ((toStrength - fromStrength) * eased)
            )

            if progress >= 1.0 then return true end
            Wait(0)
        end

        return false
    end

    CreateThread(function()
        if not animateDepthOfField(
            normalNear, normalFar, normalStrength,
            blurNear, blurFar, blurStrength,
            focusRack.BlurInDuration or 220
        ) then return end

        local holdUntil = GetGameTimer() + math.max(0, tonumber(focusRack.HoldDuration) or 120)
        while isValid() and GetGameTimer() < holdUntil do
            if state.selectionLocked then
                restoreCameraDepthOfField()
                return
            end
            Wait(0)
        end
        if not isValid() then return end

        animateDepthOfField(
            blurNear, blurFar, blurStrength,
            normalNear, normalFar, normalStrength,
            focusRack.FocusDuration or 1050
        )
    end)
end

local function applyCameraBreathing(horizontal, depth, vertical, lookVertical)
    if not state.camera then return end

    local cameraOffset = Config.Scene.CameraOffset
    local lookOffset = Config.Scene.CameraLookAt
    local cameraPosition = sceneOffset(vector3(
        cameraOffset.x + horizontal,
        cameraOffset.y + depth,
        cameraOffset.z + vertical
    ))
    local lookAt = sceneOffset(vector3(
        lookOffset.x,
        lookOffset.y,
        lookOffset.z + lookVertical
    ))

    SetCamCoord(state.camera, cameraPosition.x, cameraPosition.y, cameraPosition.z)
    PointCamAtCoord(state.camera, lookAt.x, lookAt.y, lookAt.z)
end

local function preparePed(position, alpha, frozen)
    local ped = PlayerPedId()
    local coords = state.background.coords
    state.playerPed = ped
    SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
    SetEntityHeading(ped, coords.w)
    FreezeEntityPosition(ped, frozen == true)
    SetEntityCollision(ped, true, true)
    SetPedAoBlobRendering(ped, true)
    SetEntityAlpha(ped, alpha or 255, false)
end

local function normalizedSkin(character)
    local skin = character and character.skin or nil
    if type(skin) ~= 'table' or not next(skin) then
        skin = character and character.sex == 'f' and Config.DefaultSkin.female or Config.DefaultSkin.male
    end
    if skin.sex == nil then skin.sex = character and character.sex == 'f' and 1 or 0 end
    return skin
end

local function requestAnimDict(name)
    if not name then return false end
    RequestAnimDict(name)
    local timeout = GetGameTimer() + 3000
    while not HasAnimDictLoaded(name) and GetGameTimer() < timeout do Wait(20) end
    return HasAnimDictLoaded(name)
end

local function playArrivalAnimation(ped)
    local style = state.animation
    if not style or not style.arrivalDict or not style.arrivalAnim then return end
    if requestAnimDict(style.arrivalDict) then
        TaskPlayAnim(ped, style.arrivalDict, style.arrivalAnim, 4.0, -2.0,
            Config.Scene.ArrivalAnimationDuration, 48, 0.0, false, false, false)
    end
end

local function finishTransition(character)
    state.transitionBusy = false
    if state.pendingTransition ~= nil then
        local pending = state.pendingTransition
        state.pendingTransition = nil
        SetTimeout(0, function() TriggerEvent('coii_multicharacter:internalTransition', pending) end)
    end
end

local function transitionToCharacter(character, onStarted)
    if state.transitionBusy then
        state.pendingTransition = character or false
        return
    end
    state.transitionBusy = true
    state.characterTransitionRevision = state.characterTransitionRevision + 1
    local characterTransitionRevision = state.characterTransitionRevision
    if character then startFocusRack() end
    local transitionRevision = state.sceneRevision

    SetTimeout(12000, function()
        if state.active
            and state.transitionBusy
            and state.sceneRevision == transitionRevision
            and state.characterTransitionRevision == characterTransitionRevision
            and recoverSelection then
            recoverSelection(localizedText('selection_request_failed'))
        end
    end)

    if not character then
        SetEntityAlpha(PlayerPedId(), 0, false)
        if onStarted then onStarted() end
        SetTimeout(500, function() finishTransition(character) end)
        return
    end

    local skin = normalizedSkin(character)
    local center = sceneOffset(vector3(0.0, 0.0, 0.0))

    local function startIncoming()
        local ped = PlayerPedId()
        preparePed(center, 0, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        ClearPedTasksImmediately(ped)
        SetEntityVisible(ped, true, false)

        local arrivalStyle = state.animation
        if arrivalStyle and arrivalStyle.arrivalDict then
            RequestAnimDict(arrivalStyle.arrivalDict)
        end

        if onStarted then onStarted() end

        ResetEntityAlpha(ped)
        Citizen.InvokeNative(0x1F4ED342ACEFE62D, ped, false, false)

        CreateThread(function()
            local fadeTimeout = GetGameTimer() + math.max(500, tonumber(Config.Scene.CharacterFadeTimeout) or 1200)

            while NetworkIsEntityFading(ped) and GetGameTimer() < fadeTimeout do
                if transitionRevision ~= state.sceneRevision then
                    ResetEntityAlpha(ped)
                    state.transitionBusy = false
                    return
                end
                Wait(0)
            end

            ResetEntityAlpha(ped)
            SetEntityCoordsNoOffset(ped, center.x, center.y, center.z, false, false, false)
            SetEntityHeading(ped, state.background.coords.w)
            FreezeEntityPosition(ped, true)
            playArrivalAnimation(ped)
            finishTransition(character)
        end)
    end

    SetEntityAlpha(PlayerPedId(), 0, false)
    if not state.spawnedPreview then
        ESX.SpawnPlayer(skin, center, function()
            state.spawnedPreview = true
            setupCamera()
            startIncoming()
        end)
    else
        TriggerEvent('skinchanger:loadSkin', skin, startIncoming)
    end
end

AddEventHandler('coii_multicharacter:internalTransition', function(character)
    transitionToCharacter(character ~= false and character or nil)
end)

local function sceneOptionsForNui()
    local options = {
        timeSettingsEnabled = Config.Scene.TimeSettingsEnabled ~= false,
        weatherSettingsEnabled = Config.Scene.WeatherSettingsEnabled ~= false,
        timeFormat = Config.Scene.TimeFormat,
        defaults = defaultScenePreferences(),
        backgrounds = {},
        animations = {},
        weather = {}
    }
    for i = 1, #Config.Backgrounds do
        options.backgrounds[i] = { id = Config.Backgrounds[i].id, label = Config.Backgrounds[i].label }
    end
    for i = 1, #Config.AnimationStyles do
        options.animations[i] = { id = Config.AnimationStyles[i].id, label = Config.AnimationStyles[i].label }
    end
    for i = 1, #Config.WeatherPresets do
        options.weather[i] = { id = Config.WeatherPresets[i].id, label = Config.WeatherPresets[i].label }
    end
    return options
end

local function musicTracksForNui()
    local music = Config.Music or {}
    local folder = tostring(music.Folder or 'music'):gsub('\\', '/'):gsub('^/*', ''):gsub('/*$', '')
    local configuredTracks = type(music.Tracks) == 'table' and music.Tracks or {}
    local tracks = {}

    for i = 1, #configuredTracks do
        local entry = configuredTracks[i]
        local filename = type(entry) == 'table' and entry.File or entry

        if type(filename) == 'string' and filename:lower():match('%.mp3$') then
            local fallbackLabel = filename:gsub('%.[mM][pP]3$', ''):gsub('[-_]+', ' '):upper()
            tracks[#tracks + 1] = {
                name = type(entry) == 'table' and entry.Label or fallbackLabel,
                file = ('%s/%s'):format(folder, filename)
            }
        end
    end

    return tracks
end

local function applySceneSettings(data, relocate)
    data = type(data) == 'table' and data or {}
    local previousBackground = state.background and state.background.id
    local previousAnimation = state.animation and state.animation.id
    state.background = findById(Config.Backgrounds, data.backgroundId or state.scenePreferences.backgroundId)
    state.animation = findById(Config.AnimationStyles, data.animationId or state.scenePreferences.animationId)
    local weather = findById(Config.WeatherPresets, data.weatherId or state.scenePreferences.weatherId)

    state.scenePreferences.backgroundId = state.background.id
    state.scenePreferences.animationId = state.animation.id
    state.scenePreferences.weatherId = weather.id
    state.scenePreferences.time = math.max(0, math.min(1439, tonumber(data.time) or state.scenePreferences.time))
    if state.active then applyEnvironment() end

    if state.active and (relocate or previousBackground ~= state.background.id) then
        state.sceneRevision = state.sceneRevision + 1
        state.transitionBusy = false
        state.pendingTransition = nil
        local center = sceneOffset(vector3(0.0, 0.0, 0.0))
        RequestCollisionAtCoord(center.x, center.y, center.z)
        preparePed(center, GetEntityAlpha(PlayerPedId()), true)
        setupCamera()
    elseif state.active and previousAnimation ~= state.animation.id and GetEntityAlpha(PlayerPedId()) > 0 then
        playArrivalAnimation(PlayerPedId())
    end
end

local function closeNui()
    state.focusRackRevision = state.focusRackRevision + 1
    restoreCameraDepthOfField()
    state.nuiOpen = false
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
end

local function openNui(characters, slotConfig, selectedIndex)
    local timeout = GetGameTimer() + 10000
    while not state.nuiReady and GetGameTimer() < timeout do Wait(50) end

    if not state.nuiReady then
        state.nuiOpen = false
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        DoScreenFadeIn(0)
        ESX.ShowNotification(localizedText('interface_load_failed'))
        return false
    end

    state.nuiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        characters = characters,
        slotConfig = slotConfig,
        musicTracks = musicTracksForNui(),
        sceneOptions = sceneOptionsForNui(),
        localeOptions = {
            defaultLocale = IsSupportedLocale(Config.Locale) and Config.Locale or 'en',
            languages = LocaleLanguages,
            translations = Locales
        },
        preferences = state.preferences,
        selectedIndex = selectedIndex or 1
    })
    return true
end

recoverSelection = function(message)
    if not state.active then return end

    state.selectionRequestRevision = state.selectionRequestRevision + 1
    state.sceneRevision = state.sceneRevision + 1
    state.selectionLocked = false
    state.transitionBusy = false
    state.pendingTransition = nil
    state.characterTransitionRevision = state.characterTransitionRevision + 1

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        local center = sceneOffset(vector3(0.0, 0.0, 0.0))
        ClearPedTasksImmediately(ped)
        ResetEntityAlpha(ped)
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        SetPedAoBlobRendering(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityCoordsNoOffset(ped, center.x, center.y, center.z, false, false, false)
        SetEntityHeading(ped, state.background.coords.w)
        FreezeEntityPosition(ped, true)
    end

    setupCamera()
    if openNui(state.characterList, state.slotConfig, state.selectedSlot) then
        SendNUIMessage({ action = 'selectionFailed', message = message })
    else
        ESX.ShowNotification(message or localizedText('selection_request_failed'))
    end
    TriggerServerEvent('coii_multicharacter:requestCharacters')
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(400) end
end

local function firstPreviewCharacter(characters, selectedIndex)
    for i = 1, #characters do
        if characters[i].slot == selectedIndex and not characters[i].disabled then return characters[i] end
    end
    for i = 1, #characters do
        if not characters[i].disabled then return characters[i] end
    end
end

local function beginSelection()
    if state.active then return end
    state.active = true
    state.spawnedPreview = false
    state.characters = {}
    state.characterList = {}
    state.transitionBusy = false
    state.selectionLocked = false
    state.pendingTransition = nil
    ESX.PlayerLoaded = false
    ESX.PlayerData = {}

    applySceneSettings(state.scenePreferences, false)
    DoScreenFadeOut(0)
    local center = sceneOffset(vector3(0.0, 0.0, 0.0))
    RequestCollisionAtCoord(center.x, center.y, center.z)
    SetPlayerControl(PlayerId(), false, 0)
    setHudHidden(true)
    setupCamera()

    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    TriggerEvent('esx:loadingScreenOff')

    state.selectionRequestRevision = state.selectionRequestRevision + 1
    local requestRevision = state.selectionRequestRevision
    TriggerServerEvent('coii_multicharacter:requestCharacters')

    SetTimeout(15000, function()
        if not state.active
            or state.nuiOpen
            or state.selectionRequestRevision ~= requestRevision then return end

        TriggerServerEvent('coii_multicharacter:requestCharacters')
        SetTimeout(15000, function()
            if not state.active
                or state.nuiOpen
                or state.selectionRequestRevision ~= requestRevision then return end

            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            DoScreenFadeIn(0)
            ESX.ShowNotification(localizedText('selection_request_failed'))
        end)
    end)
end

RegisterNetEvent('coii_multicharacter:open', function(characters, slotConfig, selectedIndex, preferences)
    state.selectionRequestRevision = state.selectionRequestRevision + 1
    state.characters = {}
    state.characterList = characters
    state.slotConfig = slotConfig
    state.selectedSlot = tonumber(selectedIndex) or 1
    state.selectionLocked = false
    state.preferences = type(preferences) == 'table' and preferences or nil
    if state.preferences then applySceneSettings(state.preferences, false) end
    for i = 1, #characters do state.characters[characters[i].slot] = characters[i] end

    local preview = firstPreviewCharacter(characters, state.selectedSlot)
    if preview then
        transitionToCharacter(preview, function()
            DoScreenFadeIn(650)
            openNui(characters, slotConfig, state.selectedSlot)
        end)
    else
        local center = sceneOffset(vector3(0.0, 0.0, 0.0))
        preparePed(center, 0, true)
        DoScreenFadeIn(500)
        openNui(characters, slotConfig, state.selectedSlot)
    end
end)

RegisterNetEvent('coii_multicharacter:selectionAccepted', function()
    closeNui()
    DoScreenFadeOut(500)
end)

RegisterNetEvent('coii_multicharacter:selectionFailed', function(message)
    recoverSelection(message or localizedText('selection_request_failed'))
end)

RegisterNetEvent('coii_multicharacter:beginRegistration', function(slot)
    state.selectionRequestRevision = state.selectionRequestRevision + 1
    state.selectedSlot = slot
    closeNui()
    SetPedAoBlobRendering(PlayerPedId(), false)
    SetEntityAlpha(PlayerPedId(), 0, false)
    TriggerEvent('esx_identity:showRegisterIdentity')
end)

RegisterNetEvent('coii_multicharacter:notify', notify)

RegisterNetEvent('coii_multicharacter:purchaseStatus', function(success, message)
    SendNUIMessage({ action = 'purchaseStatus', success = success, message = message })
end)

RegisterNetEvent('coii_multicharacter:deleteStatus', function(success, message)
    SendNUIMessage({ action = 'deleteStatus', success = success, message = message })
end)

local function startPlayTransition(slot)
    local transition = Config.Scene.PlayTransition or {}
    local duration = math.max(3000, math.min(5000, tonumber(transition.Duration) or 4000))
    local fadeDuration = math.max(250, math.min(duration, tonumber(transition.FadeOutDuration) or 850))
    local cameraTarget = sceneOffset(transition.CameraOffset or Config.Scene.CameraOffset)
    local lookTarget = sceneOffset(transition.CameraLookAt or Config.Scene.CameraLookAt)
    local lookStart = sceneOffset(Config.Scene.CameraLookAt)
    local cameraStart = state.camera and GetCamCoord(state.camera) or cameraTarget
    local startFov = state.camera and GetCamFov(state.camera) or 38.0
    local targetFov = tonumber(transition.CameraFov) or 32.0

    state.sceneRevision = state.sceneRevision + 1
    state.selectionRequestRevision = state.selectionRequestRevision + 1
    state.characterTransitionRevision = state.characterTransitionRevision + 1
    local requestRevision = state.selectionRequestRevision
    state.transitionBusy = false
    state.pendingTransition = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'selectionCinematic', duration = duration })

    local ped = PlayerPedId()
    ResetEntityAlpha(ped)
    FreezeEntityPosition(ped, true)
    playArrivalAnimation(ped)

    CreateThread(function()
        local startedAt = GetGameTimer()
        local fadeStarted = false

        while state.active and state.selectionLocked do
            local elapsed = GetGameTimer() - startedAt
            local progress = math.min(1.0, elapsed / duration)
            local easedProgress = progress * progress * (3.0 - (2.0 * progress))

            if state.camera then
                SetCamCoord(state.camera,
                    cameraStart.x + ((cameraTarget.x - cameraStart.x) * easedProgress),
                    cameraStart.y + ((cameraTarget.y - cameraStart.y) * easedProgress),
                    cameraStart.z + ((cameraTarget.z - cameraStart.z) * easedProgress))
                PointCamAtCoord(state.camera,
                    lookStart.x + ((lookTarget.x - lookStart.x) * easedProgress),
                    lookStart.y + ((lookTarget.y - lookStart.y) * easedProgress),
                    lookStart.z + ((lookTarget.z - lookStart.z) * easedProgress))
                SetCamFov(state.camera, startFov + ((targetFov - startFov) * easedProgress))
            end

            if not fadeStarted and elapsed >= duration - fadeDuration then
                fadeStarted = true
                DoScreenFadeOut(fadeDuration)
            end

            if progress >= 1.0 then break end
            Wait(0)
        end

        if state.active and state.selectionLocked then
            if not IsScreenFadedOut() then DoScreenFadeOut(0) end
            TriggerServerEvent('coii_multicharacter:chooseCharacter', slot, false)
            SetTimeout(20000, function()
                if state.active
                    and state.selectionLocked
                    and state.selectionRequestRevision == requestRevision then
                    recoverSelection(localizedText('selection_request_failed'))
                end
            end)
        end
    end)
end

RegisterNUICallback('nuiReady', function(data, callback)
    state.nuiReady = true
    if data and data.scenePreferences then
        local saved = data.scenePreferences
        state.scenePreferences.backgroundId = saved.backgroundId or state.scenePreferences.backgroundId
        state.scenePreferences.animationId = saved.animationId or state.scenePreferences.animationId
        state.scenePreferences.time = tonumber(saved.time) or state.scenePreferences.time
        state.scenePreferences.weatherId = saved.weatherId or state.scenePreferences.weatherId
        applySceneSettings(state.scenePreferences, false)
    end
    callback({ ok = true })
end)

RegisterNUICallback('backgroundSettings', function(data, callback)
    applySceneSettings(data, false)
    callback({ ok = true })
end)

RegisterNUICallback('savePreferences', function(data, callback)
    data = type(data) == 'table' and data or {}
    state.preferences = data
    applySceneSettings(data, false)
    TriggerServerEvent('coii_multicharacter:savePreferences', data)
    callback({ ok = true })
end)

RegisterNUICallback('changeCharacter', function(data, callback)
    data = type(data) == 'table' and data or {}
    local character = data.character or {}
    local slot = tonumber(character.slot or data.index)
    if not slot or state.selectionLocked then callback({ ok = false }) return end
    state.selectedSlot = slot

    local stored = state.characters[slot]
    if stored and not stored.disabled then
        transitionToCharacter(stored)
    else
        transitionToCharacter(nil)
    end
    callback({ ok = true })
end)

RegisterNUICallback('selectCharacter', function(data, callback)
    data = type(data) == 'table' and data or {}
    local slot = tonumber(data.character and data.character.slot or data.index)
    local character = slot and state.characters[slot]
    if not slot or not character or character.disabled or state.selectionLocked then
        callback({ ok = false })
        return
    end

    state.selectionLocked = true
    state.selectedSlot = slot
    callback({ ok = true })
    startPlayTransition(slot)
end)

RegisterNUICallback('createCharacter', function(data, callback)
    data = type(data) == 'table' and data or {}
    local slot = tonumber(data.slot)
    local totalSlots = state.slotConfig and tonumber(state.slotConfig.totalSlots) or 0
    local unlockedSlots = state.slotConfig and tonumber(state.slotConfig.unlockedSlots) or totalSlots
    local allowed = slot
        and slot % 1 == 0
        and slot >= 1
        and slot <= totalSlots
        and slot <= unlockedSlots
        and not state.characters[slot]
        and not state.selectionLocked

    if allowed then
        state.selectionLocked = true
        state.selectionRequestRevision = state.selectionRequestRevision + 1
        local requestRevision = state.selectionRequestRevision
        TriggerServerEvent('coii_multicharacter:chooseCharacter', slot, true)
        SetTimeout(20000, function()
            if state.active
                and state.selectionLocked
                and state.selectionRequestRevision == requestRevision then
                recoverSelection(localizedText('selection_request_failed'))
            end
        end)
    end
    callback({ ok = allowed == true })
end)

RegisterNUICallback('deleteCharacter', function(data, callback)
    data = type(data) == 'table' and data or {}
    local slot = tonumber(data.slot)
    local character = slot and state.characters[slot]
    local allowed = Config.CanDelete and slot and character and not character.disabled and not state.selectionLocked

    if allowed then TriggerServerEvent('coii_multicharacter:deleteCharacter', slot) end
    callback({ ok = allowed == true })
end)

RegisterNUICallback('buySlot', function(data, callback)
    data = type(data) == 'table' and data or {}
    local slot = tonumber(data.slot)
    if slot then TriggerServerEvent('coii_multicharacter:requestPurchase', slot) end
    callback({ ok = slot ~= nil })
end)

RegisterNUICallback('close', function(_, callback)
    if Config.AllowClose then closeNui() else notify(localizedText('select_character_continue')) end
    callback({ ok = Config.AllowClose })
end)

local function openSkinCreator(playerData)
    local finished = false
    local defaultSkin = playerData.sex == 'f' and Config.DefaultSkin.female or Config.DefaultSkin.male
    TriggerEvent('skinchanger:loadSkin', defaultSkin, function()
        DoScreenFadeIn(500)
        TriggerEvent('esx_skin:openSaveableMenu', function() finished = true end, function() finished = true end)
    end)
    while not finished do Wait(100) end
    return exports['skinchanger']:GetSkin()
end

RegisterNetEvent('esx:playerLoaded', function(playerData, isNew, skin)
    playerData = type(playerData) == 'table' and playerData or {}
    state.selectionRequestRevision = state.selectionRequestRevision + 1
    ESX.PlayerLoaded = true
    DoScreenFadeOut(500)
    awaitFadeOut()
    clearEnvironment()

    if isNew or type(skin) ~= 'table' or not next(skin) then
        skin = openSkinCreator(playerData)
        DoScreenFadeOut(500)
        awaitFadeOut()
    else
        TriggerEvent('skinchanger:loadSkin', skin)
    end

    local spawn = playerData.coords
    if not spawn then
        local esxConfig = ESX.GetConfig()
        local spawns = esxConfig and esxConfig.DefaultSpawns or {}
        spawn = #spawns > 0
            and spawns[math.random(1, #spawns)]
            or vector4(-269.4, -955.3, 31.2, 205.0)
    end

    destroyCamera()
    local spawnCompleted = false
    local spawnRevision = state.selectionRequestRevision
    ESX.SpawnPlayer(skin, spawn, function()
        local ped = PlayerPedId()
        ResetPedMovementClipset(ped, 0.0)
        ClearPedTasksImmediately(ped)
        ResetEntityAlpha(ped)
        SetEntityVisible(ped, true, false)
        SetPedAoBlobRendering(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, false)
        FreezeEntityPosition(ped, false)
        SetEntityCollision(ped, true, true)
        SetPlayerControl(PlayerId(), true, 0)
        setHudHidden(false)

        state.active = false
        state.spawnedPreview = false
        state.characters = {}
        state.characterList = {}
        state.transitionBusy = false
        state.selectionLocked = false
        state.pendingTransition = nil

        DoScreenFadeIn(750)
        awaitFadeIn()
        TriggerServerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:onPlayerSpawn')
        TriggerEvent('esx:restoreLoadout')
        spawnCompleted = true
    end)

    SetTimeout(20000, function()
        if spawnCompleted or state.selectionRequestRevision ~= spawnRevision then return end

        local ped = PlayerPedId()
        if DoesEntityExist(ped) then
            local x = tonumber(spawn.x) or 0.0
            local y = tonumber(spawn.y) or 0.0
            local z = tonumber(spawn.z) or 72.0
            local heading = tonumber(spawn.w or spawn.heading) or 0.0
            SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
            SetEntityHeading(ped, heading)
            ResetEntityAlpha(ped)
            SetEntityVisible(ped, true, false)
            SetEntityCollision(ped, true, true)
            SetBlockingOfNonTemporaryEvents(ped, false)
            FreezeEntityPosition(ped, false)
        end

        state.active = false
        state.selectionLocked = false
        SetPlayerControl(PlayerId(), true, 0)
        setHudHidden(false)
        DoScreenFadeIn(0)
        ESX.ShowNotification(localizedText('spawn_failed'))
    end)
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    closeNui()
    destroyCamera()
    clearEnvironment()
    state.active = false
    state.spawnedPreview = false
    DoScreenFadeOut(500)
    Wait(1000)
    TriggerEvent('esx_skin:resetFirstSpawn')
    beginSelection()
end)

if Config.Relog then
    RegisterCommand('relog', function()
        if not state.active and state.canRelog then
            state.canRelog = false
            TriggerServerEvent('coii_multicharacter:relog')
            SetTimeout(10000, function() state.canRelog = true end)
        end
    end, false)
end

CreateThread(function()
    while not NetworkIsPlayerActive(PlayerId()) do Wait(100) end
    if ESX.DisableSpawnManager then ESX.DisableSpawnManager() end
    if not ESX.PlayerLoaded then beginSelection() end
end)

CreateThread(function()
    while true do
        if state.active then
            applyEnvironment()
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

CreateThread(function()
    local currentHorizontal = 0.0
    local currentDepth = 0.0
    local currentVertical = 0.0
    local currentLook = 0.0
    local lastCamera = nil

    while true do
        local camera = state.camera
        local breathing = type(Config.Scene.CameraBreathing) == 'table' and Config.Scene.CameraBreathing or nil

        if camera ~= lastCamera then
            currentHorizontal = 0.0
            currentDepth = 0.0
            currentVertical = 0.0
            currentLook = 0.0
            lastCamera = camera
        end

        local canBreathe = state.active
            and state.nuiOpen
            and camera
            and breathing
            and breathing.Enabled
            and not state.transitionBusy
            and not state.selectionLocked

        local targetHorizontal = 0.0
        local targetDepth = 0.0
        local targetVertical = 0.0
        local targetLook = 0.0

        if canBreathe then
            local phase = (GetGameTimer() / 1000.0) * (tonumber(breathing.Speed) or 0.38)
            targetHorizontal = math.sin(phase) * (tonumber(breathing.HorizontalAmplitude) or 0.035)
            targetDepth = math.sin((phase * 0.73) + 1.4) * (tonumber(breathing.DepthAmplitude) or 0.025)
            targetVertical = math.sin((phase * 0.87) + 0.8) * (tonumber(breathing.VerticalAmplitude) or 0.018)
            targetLook = math.sin((phase * 0.63) + 2.1) * (tonumber(breathing.LookAmplitude) or 0.012)
        end

        local hasOffset = math.abs(currentHorizontal) > 0.0001
            or math.abs(currentDepth) > 0.0001
            or math.abs(currentVertical) > 0.0001
            or math.abs(currentLook) > 0.0001

        if canBreathe or (camera and not state.selectionLocked and hasOffset) then
            local response = math.max(0.1, tonumber(breathing and breathing.Response) or 1.8)
            local blend = 1.0 - math.exp(-response * GetFrameTime())
            currentHorizontal = currentHorizontal + ((targetHorizontal - currentHorizontal) * blend)
            currentDepth = currentDepth + ((targetDepth - currentDepth) * blend)
            currentVertical = currentVertical + ((targetVertical - currentVertical) * blend)
            currentLook = currentLook + ((targetLook - currentLook) * blend)

            applyCameraBreathing(currentHorizontal, currentDepth, currentVertical, currentLook)
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- Population density natives and local visibility are client-only. They are
-- asserted only during selection, then naturally reset on the next frame.
CreateThread(function()
    local hiddenPeds = {}
    local hiddenVehicles = {}
    local nextScan = 0

    while true do
        local population = Config.Scene.LocalPopulation

        if state.active and population and population.Enabled then
            SetPedDensityMultiplierThisFrame(0.0)
            SetScenarioPedDensityMultiplierThisFrame(0.0, 0.0)
            SetVehicleDensityMultiplierThisFrame(0.0)
            SetRandomVehicleDensityMultiplierThisFrame(0.0)
            SetParkedVehicleDensityMultiplierThisFrame(0.0)
            SetAmbientVehicleRangeMultiplierThisFrame(0.0)

            local now = GetGameTimer()
            if now >= nextScan then
                hiddenPeds = {}
                hiddenVehicles = {}

                local sceneCoords = state.background.coords
                local radius = math.max(25.0, tonumber(population.Radius) or 180.0)
                local radiusSquared = radius * radius
                local seenVehicles = {}

                for _, ped in ipairs(GetGamePool('CPed')) do
                    if DoesEntityExist(ped) and not IsPedAPlayer(ped) then
                        local pedCoords = GetEntityCoords(ped)
                        local x = pedCoords.x - sceneCoords.x
                        local y = pedCoords.y - sceneCoords.y
                        local z = pedCoords.z - sceneCoords.z

                        if x * x + y * y + z * z <= radiusSquared then
                            hiddenPeds[#hiddenPeds + 1] = ped

                            if population.HideNpcVehicles then
                                local vehicle = GetVehiclePedIsIn(ped, false)
                                if vehicle ~= 0
                                    and GetPedInVehicleSeat(vehicle, -1) == ped
                                    and not seenVehicles[vehicle] then
                                    seenVehicles[vehicle] = true
                                    hiddenVehicles[#hiddenVehicles + 1] = vehicle
                                end
                            end
                        end
                    end
                end

                nextScan = now + math.max(50, tonumber(population.ScanInterval) or 250)
            end

            for i = 1, #hiddenPeds do
                if DoesEntityExist(hiddenPeds[i]) then
                    SetEntityLocallyInvisible(hiddenPeds[i])
                end
            end

            for i = 1, #hiddenVehicles do
                if DoesEntityExist(hiddenVehicles[i]) then
                    SetEntityLocallyInvisible(hiddenVehicles[i])
                end
            end

            Wait(0)
        else
            hiddenPeds = {}
            hiddenVehicles = {}
            nextScan = 0
            Wait(500)
        end
    end
end)

-- GTA requires high-quality depth of field to be requested every rendered frame.
CreateThread(function()
    while true do
        local depthOfField = Config.Scene.DepthOfField
        if state.active and state.camera and depthOfField and depthOfField.Enabled then
            SetUseHiDof()
            Wait(0)
        else
            Wait(500)
        end
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    state.active = false
    state.nuiOpen = false
    state.selectionLocked = false
    state.transitionBusy = false
    state.pendingTransition = nil
    state.sceneRevision = state.sceneRevision + 1
    state.selectionRequestRevision = state.selectionRequestRevision + 1
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ action = 'close' })
    destroyCamera()
    clearEnvironment()
    setHudHidden(false)

    local ped = PlayerPedId()
    if DoesEntityExist(ped) then
        ClearPedTasksImmediately(ped)
        ResetPedMovementClipset(ped, 0.0)
        ResetEntityAlpha(ped)
        SetEntityVisible(ped, true, false)
        SetEntityCollision(ped, true, true)
        SetPedAoBlobRendering(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, false)
        FreezeEntityPosition(ped, false)
    end

    SetPlayerControl(PlayerId(), true, 0)
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(0) end
end)
