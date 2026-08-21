Config = {}

--[[===========================================================================
    COII MULTICHARACTER
    Configuration
=============================================================================]]

-- GENERAL --------------------------------------------------------------------
Config.RequiredResourceName = 'esx_multicharacter'
Config.Prefix               = 'char'
Config.Locale               = 'en' -- en | hr | de | sl | fr
Config.AutoMigrate          = true
Config.Debug                = false
Config.CanDelete            = true
Config.Relog                = true
Config.AllowClose           = false

-- CHARACTER SLOTS ------------------------------------------------------------
Config.PaidSlots = {
    Enabled                        = true,
    FreeSlots                      = 2,
    TotalSlots                     = 3,
    PriceLabel                     = 'PAID CHARACTER SLOT',
    GrandfatherExistingCharacters = true,
    StoreEnabled                   = true,
    StoreUrl                       = 'https://discord.gg/invite/sokacdev'
}

-- PLAYER DEFAULTS ------------------------------------------------------------
Config.PreferenceDefaults = {
    Locale                   = Config.Locale,
    Theme                    = 'light',
    CustomUiColor            = '#FFFFFF',
    CustomSettingsBackground = '#F5F5F3',
    CustomSettingsText       = '#111111',
    MusicTrack               = 2, -- 0 disables music
    MusicVolume              = 15,
    InterfaceScale           = 106
}

-- MUSIC ----------------------------------------------------------------------
Config.Music = {
    Folder = 'music',

    Tracks = {
        { File = 'dream-ambience.mp3', Label = 'DREAM AMBIENCE' },
        { File = 'contemplation.mp3',  Label = 'CONTEMPLATION' }
    }
}

-- SELECTION SCENE ------------------------------------------------------------
Config.Scene = {
    TimeSettingsEnabled      = false,
    WeatherSettingsEnabled   = false,
    DefaultBackground        = 'desert',
    DefaultAnimation         = 'confident',
    DefaultTime              = 720, -- minutes after midnight
    DefaultWeather           = 'EXTRASUNNY',
    TimeFormat               = '24HR', -- 24HR | 12HR
    CharacterFadeTimeout     = 1200,
    ArrivalAnimationDuration = 2200,

    LocalPopulation = {
        Enabled         = true,
        Radius          = 180.0,
        ScanInterval    = 250,
        HideNpcVehicles = true
    },

    DepthOfField = {
        Enabled  = true,
        NearDof  = 2.0,
        FarDof   = 5.5,
        Strength = 1.0
    },

    FocusRack = {
        Enabled         = true,
        BlurInDuration  = 220,
        HoldDuration    = 120,
        FocusDuration   = 1050,
        BlurNearDof     = 0.25,
        BlurFarDof      = 1.15,
        BlurStrength    = 1.0
    },

    CameraBreathing = {
        Enabled             = true,
        Speed               = 0.38,
        Response            = 1.8,
        HorizontalAmplitude = 0.035,
        DepthAmplitude      = 0.025,
        VerticalAmplitude   = 0.018,
        LookAmplitude       = 0.012
    },

    CameraOffset = vector3(0.95, 5.1, 0.75),
    CameraLookAt = vector3(-1.1, 0.0, 0.65),

    PlayTransition = {
        Duration        = 4000,
        FadeOutDuration = 850,
        CameraOffset    = vector3(0.70, 3.65, 0.82),
        CameraLookAt    = vector3(-1.1, 0.0, 0.70),
        CameraFov       = 32.0
    }
}

-- LOCATIONS ------------------------------------------------------------------
Config.Backgrounds = {
    { id = 'morgue',    label = 'MORGUE',               coords = vector4(252.9835, -1354.7893, 24.5378, 171.6970) },
    { id = 'penthouse', label = 'PENTHOUSE',            coords = vector4(-767.5109, 610.8865, 140.3307, 108.1741) },
    { id = 'chiliad',   label = 'MOUNTAIN CHILLIAD',    coords = vector4(502.1399, 5594.0747, 795.5482, 45.9737) },
    { id = 'desert',    label = 'SANDY SHORES DESERT',  coords = vector4(431.3923, 3076.1860, 41.9441, 324.7680) },
    { id = 'forest',    label = 'FOREST',               coords = vector4(-527.1254, 4450.7480, 38.2624, 357.6826) },
    { id = 'pier',      label = 'LOS SANTOS PIER',      coords = vector4(-1700.7257, -1091.3569, 13.1523, 85.8225) }
}

-- CHARACTER ANIMATIONS -------------------------------------------------------
Config.AnimationStyles = {
    {
        id      = 'normal',
        label   = 'NORMAL',
        clipset = nil
    },
    {
        id          = 'confident',
        label       = 'CONFIDENT',
        clipset     = 'move_m@confident',
        arrivalDict = 'anim@mp_player_intcelebrationmale@thumbs_up',
        arrivalAnim = 'thumbs_up'
    },
    {
        id          = 'relaxed',
        label       = 'RELAXED',
        clipset     = 'move_m@casual@d',
        arrivalDict = 'amb@world_human_hang_out_street@male_a@idle_a',
        arrivalAnim = 'idle_a'
    },
    {
        id          = 'tough',
        label       = 'TOUGH',
        clipset     = 'move_m@brave',
        arrivalDict = 'anim@mp_player_intcelebrationmale@knuckle_crunch',
        arrivalAnim = 'knuckle_crunch'
    },
    {
        id          = 'business',
        label       = 'BUSINESS',
        clipset     = 'move_m@business@a',
        arrivalDict = 'anim@mp_player_intcelebrationmale@salute',
        arrivalAnim = 'salute'
    }
}

-- WEATHER --------------------------------------------------------------------
Config.WeatherPresets = {
    { id = 'EXTRASUNNY', label = 'EXTRA SUNNY' },
    { id = 'CLEAR',      label = 'CLEAR' },
    { id = 'CLOUDS',     label = 'CLOUDY' },
    { id = 'OVERCAST',   label = 'OVERCAST' },
    { id = 'SMOG',       label = 'SMOG' },
    { id = 'FOGGY',      label = 'FOGGY' },
    { id = 'RAIN',       label = 'RAIN' },
    { id = 'THUNDER',    label = 'THUNDER' }
}

-- DEFAULT SKINS --------------------------------------------------------------
Config.DefaultSkin = {
    male = { sex = 0 },
    female = { sex = 1 }
}

-- COMMANDS -------------------------------------------------------------------
Config.Commands = {
    GrantSlot     = 'grantslot',
    RevokeSlot    = 'revokeslot',
    AcePermission = 'coii_multicharacter.admin'
}
