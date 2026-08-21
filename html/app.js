const app = document.querySelector('#app');
const nameElement = document.querySelector('#character-name');
const jobElement = document.querySelector('#character-job');
const lastPlayedElement = document.querySelector('#last-played-value');
const indicators = document.querySelector('#slot-indicator');
const currentSlotElement = document.querySelector('#current-slot');
const totalSlotsElement = document.querySelector('#total-slots');
const settingsPanel = document.querySelector('#settings-panel');
const trackNameElement = document.querySelector('#track-name');
const volumeInput = document.querySelector('#music-volume');
const volumeValue = document.querySelector('#volume-value');
const interfaceSizeInput = document.querySelector('#interface-size');
const interfaceSizeValue = document.querySelector('#interface-size-value');
const localeNameElement = document.querySelector('#locale-name');
const previousLocaleButton = document.querySelector('#previous-locale');
const nextLocaleButton = document.querySelector('#next-locale');
const customThemeControls = document.querySelector('#custom-theme-controls');
const resetCustomThemeButton = document.querySelector('#reset-custom-theme');
const backgroundNameElement = document.querySelector('#background-name');
const animationNameElement = document.querySelector('#animation-name');
const sceneTimeInput = document.querySelector('#scene-time');
const sceneTimeValue = document.querySelector('#scene-time-value');
const sceneWeatherValue = document.querySelector('#scene-weather-value');
const timeSettingControl = document.querySelector('#time-setting-control');
const timeSettingLabel = document.querySelector('#time-setting-label');
const weatherSettingControl = document.querySelector('#weather-setting-control');
const weatherSettingLabel = document.querySelector('#weather-setting-label');
const previousWeatherButton = document.querySelector('#previous-weather');
const nextWeatherButton = document.querySelector('#next-weather');
const identityElement = document.querySelector('#character-identity');
const detailLabelElement = document.querySelector('#detail-label');
const slotLockLabel = document.querySelector('#slot-lock-label');
const characterActions = document.querySelector('.character-actions');
const actionButton = document.querySelector('#play');
const actionLabel = document.querySelector('#action-label');
const actionDescription = document.querySelector('#action-description');
const actionIconPath = document.querySelector('#action-icon-path');
const deleteCharacterButton = document.querySelector('#delete-character');
const deleteConfirmation = document.querySelector('#delete-confirmation');
const deleteConfirmationTitle = document.querySelector('#delete-confirmation-title');
const cancelDeleteButton = document.querySelector('#cancel-delete');
const confirmDeleteButton = document.querySelector('#confirm-delete');
const confirmDeleteLabel = document.querySelector('#confirm-delete-label');
const statusToast = document.querySelector('#status-toast');
const statusToastTitle = document.querySelector('#status-toast-title');
const statusToastMessage = document.querySelector('#status-toast-message');

let characters = [];
let selectedIndex = 0;
let settingsOpen = false;
let slotConfig = { enabled: false };
let deleteConfirmationOpen = false;
let deletionBusy = false;
let pendingDeleteSlot = null;
let deleteCountdownTimer = null;
let deleteRequestTimer = null;
let deleteCountdownDeadline = 0;
let deleteCountdownReady = false;

const deleteConfirmationDelay = 15000;

const embeddedEnglish = {};
document.querySelectorAll('[data-i18n]').forEach((element) => {
    embeddedEnglish[element.dataset.i18n] = element.textContent.trim();
});
Object.assign(embeddedEnglish, {
    music_off: 'MUSIC OFF',
    never_played: 'NEVER PLAYED',
    character_disabled: 'CHARACTER DISABLED',
    slot_status: 'SLOT STATUS',
    contact_staff: 'CONTACT SERVER STAFF',
    unavailable: 'UNAVAILABLE',
    character_is_disabled: 'CHARACTER IS DISABLED',
    character_slot: 'CHARACTER SLOT %{slot}',
    locked_slot: 'LOCKED SLOT',
    slot_access: 'SLOT ACCESS',
    purchase_required: 'PURCHASE REQUIRED',
    buy_slot: 'BUY SLOT',
    unlock_character_slot: 'UNLOCK CHARACTER SLOT',
    empty_slot: 'EMPTY SLOT %{slot}',
    available_character_slot: 'AVAILABLE CHARACTER SLOT',
    ready_to_create: 'READY TO CREATE',
    create_character: 'CREATE CHARACTER',
    use_character_slot: 'USE THIS CHARACTER SLOT',
    store_not_enabled: 'STORE IS NOT ENABLED',
    store_url_invalid: 'ADD A VALID STORE URL IN CONFIG.LUA',
    external_links_unavailable: 'EXTERNAL LINKS ARE NOT AVAILABLE',
    slot_purchase: 'SLOT PURCHASE',
    music_file_error: 'MUSIC FILE ERROR',
    could_not_load_track: 'COULD NOT LOAD %{track}',
    delete_in: 'DELETE IN %{seconds}S',
    deleting: 'DELETING...',
    delete_character_question: 'DELETE %{name}?',
    store_link_opened: 'EXTERNAL STORE LINK OPENED',
    paid_slot_test: 'PAID SLOT TEST',
    preview_test: 'PREVIEW TEST',
    create_slot_callback: 'CREATE SLOT %{slot} CALLBACK RECEIVED',
    slot_now_empty: 'SLOT %{slot} IS NOW EMPTY',
    character_deleted: 'CHARACTER DELETED',
    character_deletion_failed: 'CHARACTER DELETION FAILED',
    delete_failed: 'DELETE FAILED',
    selection_request_failed: 'CHARACTER SELECTION DID NOT RESPOND. PLEASE TRY AGAIN.',
    interface_load_failed: 'THE CHARACTER INTERFACE FAILED TO LOAD.'
});

let localeOptions = {
    defaultLocale: 'en',
    languages: [{ id: 'en', label: 'ENGLISH' }],
    translations: { en: embeddedEnglish }
};

let tracks = [{ name: embeddedEnglish.music_off, file: null }];

const defaultCustomTheme = {
    customUiColor: '#FFFFFF',
    customSettingsBackground: '#F5F5F3',
    customSettingsText: '#111111'
};

let savedPreferences = {};
try {
    savedPreferences = JSON.parse(localStorage.getItem('multicharacterSettings') || '{}');
} catch (_) {}

const preferences = {
    locale: typeof savedPreferences.locale === 'string' ? savedPreferences.locale : 'en',
    theme: ['light', 'dark', 'custom'].includes(savedPreferences.theme) ? savedPreferences.theme : 'light',
    customUiColor: normalizeHexColor(savedPreferences.customUiColor, defaultCustomTheme.customUiColor),
    customSettingsBackground: normalizeHexColor(savedPreferences.customSettingsBackground, defaultCustomTheme.customSettingsBackground),
    customSettingsText: normalizeHexColor(savedPreferences.customSettingsText, defaultCustomTheme.customSettingsText),
    track: Number.isFinite(Number(savedPreferences.track)) ? Number(savedPreferences.track) : 2,
    volume: Number.isFinite(Number(savedPreferences.volume)) ? Number(savedPreferences.volume) : 15,
    uiScale: Number.isFinite(Number(savedPreferences.uiScale)) ? Number(savedPreferences.uiScale) : 106,
    backgroundId: savedPreferences.backgroundId || 'pier',
    animationId: savedPreferences.animationId || 'confident',
    time: Number.isFinite(Number(savedPreferences.time)) ? Number(savedPreferences.time) : 720,
    weatherId: savedPreferences.weatherId || 'EXTRASUNNY'
};

let sceneOptions = {
    timeSettingsEnabled: true,
    weatherSettingsEnabled: true,
    timeFormat: '24HR',
    defaults: { backgroundId: 'pier', animationId: 'confident', time: 720, weatherId: 'EXTRASUNNY' },
    backgrounds: [
        { id: 'pier', label: 'LOS SANTOS PIER' },
        { id: 'sandy', label: 'SANDY SHORES' },
        { id: 'desert', label: 'GRAND SENORA DESERT' },
        { id: 'forest', label: 'PALETO FOREST' },
        { id: 'vinewood', label: 'VINEWOOD OVERLOOK' }
    ],
    animations: [
        { id: 'normal', label: 'NORMAL' },
        { id: 'confident', label: 'CONFIDENT' },
        { id: 'relaxed', label: 'RELAXED' },
        { id: 'tough', label: 'TOUGH' },
        { id: 'business', label: 'BUSINESS' }
    ],
    weather: [
        { id: 'EXTRASUNNY', label: 'EXTRA SUNNY' },
        { id: 'CLEAR', label: 'CLEAR' },
        { id: 'CLOUDS', label: 'CLOUDY' },
        { id: 'OVERCAST', label: 'OVERCAST' },
        { id: 'SMOG', label: 'SMOG' },
        { id: 'FOGGY', label: 'FOGGY' },
        { id: 'RAIN', label: 'RAIN' },
        { id: 'THUNDER', label: 'THUNDER' }
    ]
};

let audioContext = null;
const musicPlayer = new Audio();
musicPlayer.loop = true;
musicPlayer.preload = 'auto';
let scenePostTimer = null;
let preferencesPostTimer = null;
let remotePreferencesReady = false;

const isBrowserPreview = typeof GetParentResourceName !== 'function';
const resourceName = !isBrowserPreview
    ? GetParentResourceName()
    : 'multicharacter';
const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
const parallaxMotion = {
    targetX: 0,
    targetY: 0,
    currentX: 0,
    currentY: 0,
    velocityX: 0,
    velocityY: 0,
    lastFrame: 0,
    frame: null
};

function post(eventName, data = {}) {
    return fetch(`https://${resourceName}/${eventName}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => null);
}

function writeParallax(x, y) {
    const deepX = x * 9;
    const deepY = y * 6;

    app.style.setProperty('--parallax-deep-x', `${deepX.toFixed(2)}px`);
    app.style.setProperty('--parallax-deep-y', `${deepY.toFixed(2)}px`);
    app.style.setProperty('--parallax-medium-x', `${(deepX * .68).toFixed(2)}px`);
    app.style.setProperty('--parallax-medium-y', `${(deepY * .68).toFixed(2)}px`);
    app.style.setProperty('--parallax-soft-x', `${(deepX * .4).toFixed(2)}px`);
    app.style.setProperty('--parallax-soft-y', `${(deepY * .4).toFixed(2)}px`);
}

function animateParallax(timestamp) {
    const motion = parallaxMotion;
    const deltaTime = motion.lastFrame
        ? Math.min(.033, Math.max(.001, (timestamp - motion.lastFrame) / 1000))
        : 1 / 60;
    motion.lastFrame = timestamp;

    const spring = 46;
    const damping = Math.exp(-8.2 * deltaTime);
    motion.velocityX = (motion.velocityX + ((motion.targetX - motion.currentX) * spring * deltaTime)) * damping;
    motion.velocityY = (motion.velocityY + ((motion.targetY - motion.currentY) * spring * deltaTime)) * damping;
    motion.currentX += motion.velocityX * deltaTime;
    motion.currentY += motion.velocityY * deltaTime;

    motion.currentX = Math.max(-1.15, Math.min(1.15, motion.currentX));
    motion.currentY = Math.max(-1.15, Math.min(1.15, motion.currentY));
    writeParallax(motion.currentX, motion.currentY);

    const settled = Math.abs(motion.targetX - motion.currentX) < .0005
        && Math.abs(motion.targetY - motion.currentY) < .0005
        && Math.abs(motion.velocityX) < .001
        && Math.abs(motion.velocityY) < .001;

    if (settled) {
        motion.currentX = motion.targetX;
        motion.currentY = motion.targetY;
        motion.velocityX = 0;
        motion.velocityY = 0;
        motion.lastFrame = 0;
        motion.frame = null;
        writeParallax(motion.currentX, motion.currentY);
        return;
    }

    motion.frame = window.requestAnimationFrame(animateParallax);
}

function startParallaxMotion() {
    if (parallaxMotion.frame === null) {
        parallaxMotion.lastFrame = 0;
        parallaxMotion.frame = window.requestAnimationFrame(animateParallax);
    }
}

function resetParallax(immediate = false) {
    parallaxMotion.targetX = 0;
    parallaxMotion.targetY = 0;

    if (!immediate) {
        startParallaxMotion();
        return;
    }

    if (parallaxMotion.frame !== null) window.cancelAnimationFrame(parallaxMotion.frame);
    parallaxMotion.currentX = 0;
    parallaxMotion.currentY = 0;
    parallaxMotion.velocityX = 0;
    parallaxMotion.velocityY = 0;
    parallaxMotion.lastFrame = 0;
    parallaxMotion.frame = null;
    writeParallax(0, 0);
}

function updateParallax(event) {
    if (reducedMotionQuery.matches
        || !app.classList.contains('is-visible')
        || app.classList.contains('is-selecting')
        || deleteConfirmationOpen) return;

    const normalizedX = Math.max(-1, Math.min(1, (event.clientX / Math.max(window.innerWidth, 1) - .5) * 2));
    const normalizedY = Math.max(-1, Math.min(1, (event.clientY / Math.max(window.innerHeight, 1) - .5) * 2));
    parallaxMotion.targetX = normalizedX;
    parallaxMotion.targetY = normalizedY;
    startParallaxMotion();
}

function replaceLocaleTokens(template, replacements = {}) {
    return String(template).replace(/%\{([a-zA-Z0-9_]+)\}/g, (match, key) => (
        Object.prototype.hasOwnProperty.call(replacements, key) ? String(replacements[key]) : match
    ));
}

function t(key, replacements = {}) {
    const active = localeOptions.translations[preferences.locale] || {};
    const fallback = localeOptions.translations.en || embeddedEnglish;
    const template = active[key] ?? fallback[key] ?? embeddedEnglish[key] ?? key;
    return replaceLocaleTokens(template, replacements);
}

function localeIsAvailable(locale) {
    return localeOptions.languages.some((language) => language.id === locale)
        && Boolean(localeOptions.translations[locale]);
}

function configureLocales(rawOptions) {
    const rawLanguages = Array.isArray(rawOptions?.languages) ? rawOptions.languages : [];
    const rawTranslations = rawOptions?.translations && typeof rawOptions.translations === 'object'
        ? rawOptions.translations
        : {};
    const languages = rawLanguages.flatMap((language) => {
        const id = typeof language?.id === 'string' ? language.id.trim().toLowerCase() : '';
        if (!id || !rawTranslations[id] || typeof rawTranslations[id] !== 'object') return [];
        return [{ id, label: String(language.label || id).toUpperCase() }];
    });

    if (!languages.some((language) => language.id === 'en')) {
        languages.unshift({ id: 'en', label: 'ENGLISH' });
    }

    localeOptions = {
        defaultLocale: typeof rawOptions?.defaultLocale === 'string'
            ? rawOptions.defaultLocale.trim().toLowerCase()
            : 'en',
        languages,
        translations: {
            ...rawTranslations,
            en: { ...embeddedEnglish, ...(rawTranslations.en || {}) }
        }
    };

    if (!localeIsAvailable(localeOptions.defaultLocale)) localeOptions.defaultLocale = 'en';
}

function translatedOptionLabel(kind, option) {
    const key = `${kind}_${String(option.id).toLowerCase()}`;
    const translated = t(key);
    return translated === key ? option.label : translated;
}

function applyLocale(locale, persist = true) {
    const normalized = typeof locale === 'string' ? locale.trim().toLowerCase() : '';
    preferences.locale = localeIsAvailable(normalized) ? normalized : localeOptions.defaultLocale;
    document.documentElement.lang = preferences.locale;

    document.querySelectorAll('[data-i18n]').forEach((element) => {
        element.textContent = t(element.dataset.i18n);
    });

    const language = localeOptions.languages.find((entry) => entry.id === preferences.locale);
    localeNameElement.textContent = language?.label || preferences.locale.toUpperCase();
    if (tracks[0] && !tracks[0].file) tracks[0].name = t('music_off');
    if (tracks[preferences.track]) trackNameElement.textContent = tracks[preferences.track].name;
    if (characters.length) render();
    renderSceneControls();
    if (!deleteConfirmationOpen) confirmDeleteLabel.textContent = t('delete_character');
    if (persist) savePreferences();
}

function cycleLocale(direction) {
    if (localeOptions.languages.length < 2) return;
    const currentIndex = Math.max(0, localeOptions.languages.findIndex((language) => language.id === preferences.locale));
    const nextIndex = (currentIndex + direction + localeOptions.languages.length) % localeOptions.languages.length;
    applyLocale(localeOptions.languages[nextIndex].id);
}

function safeExternalUrl(value) {
    try {
        const url = new URL(String(value || '').trim());
        return url.protocol === 'https:' || url.protocol === 'http:' ? url.href : null;
    } catch (_) {
        return null;
    }
}

function openStoreUrl() {
    if (!slotConfig.storeEnabled) {
        showStatusToast(t('store_not_enabled'), t('slot_purchase'));
        return false;
    }

    const url = safeExternalUrl(slotConfig.storeUrl);
    if (!url) {
        showStatusToast(t('store_url_invalid'), t('slot_purchase'));
        return false;
    }

    if (isBrowserPreview) {
        window.open(url, '_blank', 'noopener,noreferrer');
    } else if (typeof window.invokeNative === 'function') {
        window.invokeNative('openUrl', url);
    } else {
        showStatusToast(t('external_links_unavailable'), t('slot_purchase'));
        return false;
    }

    return true;
}

function normalizeHexColor(value, fallback = '#FFFFFF') {
    const normalized = String(value || '').trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(normalized) ? normalized : fallback;
}

function hexToRgb(value) {
    const color = normalizeHexColor(value);
    return {
        r: Number.parseInt(color.slice(1, 3), 16),
        g: Number.parseInt(color.slice(3, 5), 16),
        b: Number.parseInt(color.slice(5, 7), 16)
    };
}

function rgbToHex(rgb) {
    const channel = (value) => Math.max(0, Math.min(255, Math.round(Number(value) || 0)))
        .toString(16).padStart(2, '0');
    return `#${channel(rgb.r)}${channel(rgb.g)}${channel(rgb.b)}`.toUpperCase();
}

function colorWithAlpha(value, alpha) {
    const { r, g, b } = hexToRgb(value);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

function contrastingTextColor(value) {
    const { r, g, b } = hexToRgb(value);
    const luminance = ((r * .299) + (g * .587) + (b * .114)) / 255;
    return luminance > .58 ? '#101010' : '#FFFFFF';
}

function formatLastPlayed(value) {
    if (!value) return t('never_played');
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return String(value);

    const dateLocales = { en: 'en-GB', hr: 'hr-HR', de: 'de-DE', sl: 'sl-SI', fr: 'fr-FR' };
    return new Intl.DateTimeFormat(dateLocales[preferences.locale] || preferences.locale || 'en-GB', {
        day: '2-digit', month: 'short', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
    }).format(date).replace(',', '  \u2022');
}

function characterName(character) {
    return character.name || [character.firstname, character.lastname].filter(Boolean).join(' ') || 'New character';
}

function characterJob(character) {
    const jobName = character.jobName || character.job || character.jobLabel || 'unemployed';
    const gradeLabel = character.jobGradeLabel || character.jobGrade || '';
    return gradeLabel ? `${jobName} - ${gradeLabel}` : jobName;
}

function buildMusicTracks(rawTracks) {
    const configuredTracks = Array.isArray(rawTracks) ? rawTracks : [];
    const mp3Tracks = configuredTracks.flatMap((track) => {
        const file = typeof track?.file === 'string' ? track.file.trim() : '';
        if (!file.toLowerCase().endsWith('.mp3')) return [];

        const filename = file.split('/').pop() || file;
        const fallbackName = filename.replace(/\.mp3$/i, '').replace(/[-_]+/g, ' ').toUpperCase();
        return [{ name: String(track.name || fallbackName).toUpperCase(), file }];
    });

    return [{ name: t('music_off'), file: null }, ...mp3Tracks];
}

function normalizeTrackIndex(value) {
    const index = Math.floor(Number(value));
    if (!Number.isFinite(index) || index <= 0) return 0;
    return Math.min(index, tracks.length - 1);
}

function buildCharacterSlots(rawCharacters, options = {}) {
    const suppliedCharacters = Array.isArray(rawCharacters) ? rawCharacters : [];

    const highestSuppliedSlot = suppliedCharacters.reduce((highest, character) => Math.max(highest, Number(character.slot) || 0), 0);
    const totalSlots = Math.max(Number(options.totalSlots) || suppliedCharacters.length, suppliedCharacters.length, highestSuppliedSlot);
    const freeSlots = Math.max(0, Number(options.freeSlots) || 0);
    const purchasedSlots = Math.max(0, Number(options.purchasedSlots) || 0);
    const unlockedSlots = Math.min(totalSlots, Number.isFinite(Number(options.unlockedSlots))
        ? Number(options.unlockedSlots)
        : freeSlots + purchasedSlots);
    const usesExplicitSlotNumbers = suppliedCharacters.some((character) => Number(character.slot) > 0);

    return Array.from({ length: totalSlots }, (_, index) => {
        const slotNumber = index + 1;
        const character = usesExplicitSlotNumbers
            ? suppliedCharacters.find((entry) => Number(entry.slot) === slotNumber)
            : suppliedCharacters[index];

        if (character) return { ...character, slot: slotNumber, locked: Boolean(character.locked) };
        if (index >= unlockedSlots) {
            return {
                slot: slotNumber,
                locked: true,
                priceLabel: options.priceLabel || t('paid_character_slot')
            };
        }
        return { slot: slotNumber, empty: true, locked: false };
    });
}

function render() {
    const character = characters[selectedIndex];
    if (!character) return;

    const slotNumber = Number(character.slot) || selectedIndex + 1;
    const locked = Boolean(character.locked);
    const empty = Boolean(character.empty);
    const disabled = Boolean(character.disabled);
    const canDelete = Boolean(slotConfig.canDelete) && !locked && !empty && !disabled;

    identityElement.classList.toggle('is-locked', locked);
    identityElement.classList.toggle('is-empty', empty);
    identityElement.classList.toggle('is-disabled', disabled);
    actionButton.classList.toggle('is-buy', locked);
    actionButton.classList.toggle('is-create', empty);
    actionButton.classList.toggle('is-disabled', disabled);
    deleteCharacterButton.classList.toggle('is-visible', canDelete);
    deleteCharacterButton.disabled = !canDelete || deletionBusy;
    deleteCharacterButton.setAttribute('aria-hidden', String(!canDelete));

    if (deleteConfirmationOpen && (pendingDeleteSlot !== slotNumber || !canDelete)) {
        closeDeleteConfirmation();
    }

    if (disabled) {
        nameElement.textContent = characterName(character);
        jobElement.textContent = t('character_disabled');
        detailLabelElement.textContent = t('slot_status');
        lastPlayedElement.textContent = t('contact_staff');
        actionLabel.textContent = t('unavailable');
        actionDescription.textContent = t('character_is_disabled');
        actionIconPath.setAttribute('d', 'M6 6l12 12M18 6L6 18');
    } else if (locked) {
        nameElement.textContent = t('character_slot', { slot: String(slotNumber).padStart(2, '0') });
        jobElement.textContent = t('locked_slot');
        detailLabelElement.textContent = t('slot_access');
        lastPlayedElement.textContent = t('purchase_required');
        const configuredPriceLabel = character.priceLabel || slotConfig.priceLabel;
        slotLockLabel.textContent = configuredPriceLabel && configuredPriceLabel !== 'PAID CHARACTER SLOT'
            ? configuredPriceLabel
            : t('paid_character_slot');
        actionLabel.textContent = t('buy_slot');
        actionDescription.textContent = t('unlock_character_slot');
        actionIconPath.setAttribute('d', 'M7 10V7a5 5 0 0 1 10 0v3M6 10h12v10H6z');
    } else if (empty) {
        nameElement.textContent = t('empty_slot', { slot: String(slotNumber).padStart(2, '0') });
        jobElement.textContent = t('available_character_slot');
        detailLabelElement.textContent = t('slot_status');
        lastPlayedElement.textContent = t('ready_to_create');
        actionLabel.textContent = t('create_character');
        actionDescription.textContent = t('use_character_slot');
        actionIconPath.setAttribute('d', 'M12 5v14M5 12h14');
    } else {
        nameElement.textContent = characterName(character);
        jobElement.textContent = characterJob(character);
        detailLabelElement.textContent = t('last_played');
        lastPlayedElement.textContent = formatLastPlayed(character.lastPlayed || character.last_played);
        actionLabel.textContent = t('play');
        actionDescription.textContent = t('play_as_character');
        actionIconPath.setAttribute('d', 'M9 6l8 6-8 6z');
    }

    currentSlotElement.textContent = String(slotNumber).padStart(2, '0');
    totalSlotsElement.textContent = String(characters.length).padStart(2, '0');
    indicators.replaceChildren(...characters.map((_, index) => {
        const dot = document.createElement('span');
        dot.className = `slot-dot${index === selectedIndex ? ' is-active' : ''}`;
        return dot;
    }));
}

function changeCharacter(direction) {
    if (characters.length < 2 || deleteConfirmationOpen) return;
    selectedIndex = (selectedIndex + direction + characters.length) % characters.length;
    render();
    post('changeCharacter', { character: characters[selectedIndex], index: selectedIndex + 1 });
}

function preferencesPayload() {
    return {
        locale: preferences.locale,
        theme: preferences.theme,
        customUiColor: preferences.customUiColor,
        customSettingsBackground: preferences.customSettingsBackground,
        customSettingsText: preferences.customSettingsText,
        track: preferences.track,
        volume: preferences.volume,
        uiScale: preferences.uiScale,
        backgroundId: preferences.backgroundId,
        animationId: preferences.animationId,
        time: preferences.time,
        weatherId: preferences.weatherId
    };
}

function applyStoredPreferences(saved) {
    if (!saved || typeof saved !== 'object') return;
    if (typeof saved.locale === 'string' && localeIsAvailable(saved.locale.toLowerCase())) {
        preferences.locale = saved.locale.toLowerCase();
    }
    if (saved.theme === 'light' || saved.theme === 'dark' || saved.theme === 'custom') preferences.theme = saved.theme;
    preferences.customUiColor = normalizeHexColor(saved.customUiColor, preferences.customUiColor);
    preferences.customSettingsBackground = normalizeHexColor(saved.customSettingsBackground, preferences.customSettingsBackground);
    preferences.customSettingsText = normalizeHexColor(saved.customSettingsText, preferences.customSettingsText);
    if (Number.isFinite(Number(saved.track))) preferences.track = Number(saved.track);
    if (Number.isFinite(Number(saved.volume))) preferences.volume = Number(saved.volume);
    if (Number.isFinite(Number(saved.uiScale))) preferences.uiScale = Number(saved.uiScale);
    if (typeof saved.backgroundId === 'string') preferences.backgroundId = saved.backgroundId;
    if (typeof saved.animationId === 'string') preferences.animationId = saved.animationId;
    if (Number.isFinite(Number(saved.time))) preferences.time = Number(saved.time);
    if (typeof saved.weatherId === 'string') preferences.weatherId = saved.weatherId;
}

function flushRemotePreferences() {
    if (preferencesPostTimer) window.clearTimeout(preferencesPostTimer);
    preferencesPostTimer = null;
    if (!remotePreferencesReady || isBrowserPreview) return;
    post('savePreferences', preferencesPayload());
}

function savePreferences() {
    try { localStorage.setItem('multicharacterSettings', JSON.stringify(preferences)); } catch (_) {}
    if (!remotePreferencesReady || isBrowserPreview) return;
    if (preferencesPostTimer) window.clearTimeout(preferencesPostTimer);
    preferencesPostTimer = window.setTimeout(flushRemotePreferences, 300);
}

function ensureAudio() {
    if (!audioContext) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        if (!AudioContextClass) return null;
        audioContext = new AudioContextClass();
    }
    if (audioContext.state === 'suspended') audioContext.resume().catch(() => {});
    return audioContext;
}

function playSoftClick() {
    const context = ensureAudio();
    if (!context) return;

    const duration = .026;
    const buffer = context.createBuffer(1, Math.ceil(context.sampleRate * duration), context.sampleRate);
    const channel = buffer.getChannelData(0);
    for (let index = 0; index < channel.length; index += 1) {
        const envelope = Math.pow(1 - index / channel.length, 3.5);
        channel[index] = (Math.random() * 2 - 1) * envelope;
    }

    const source = context.createBufferSource();
    const filter = context.createBiquadFilter();
    const gain = context.createGain();
    source.buffer = buffer;
    filter.type = 'bandpass';
    filter.frequency.value = 1450;
    filter.Q.value = .8;
    gain.gain.value = .075;
    source.connect(filter).connect(gain).connect(context.destination);
    source.start();
}

function playHoverSound() {
    const context = ensureAudio();
    if (!context) return;

    const now = context.currentTime;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = 'sine';
    oscillator.frequency.setValueAtTime(460, now);
    oscillator.frequency.exponentialRampToValueAtTime(620, now + .055);
    gain.gain.setValueAtTime(.0001, now);
    gain.gain.exponentialRampToValueAtTime(.018, now + .008);
    gain.gain.exponentialRampToValueAtTime(.0001, now + .06);
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(now);
    oscillator.stop(now + .065);
}

function stopMusic() {
    musicPlayer.onerror = null;
    musicPlayer.pause();
    musicPlayer.removeAttribute('src');
    musicPlayer.load();
}

function startMusic() {
    stopMusic();
    const track = tracks[preferences.track] || tracks[0];
    if (!track.file) return;

    musicPlayer.onerror = () => {
        if (app.classList.contains('is-visible')) {
            showStatusToast(t('could_not_load_track', { track: track.name }), t('music_file_error'));
        }
    };
    musicPlayer.src = track.file;
    musicPlayer.volume = preferences.volume / 100;
    musicPlayer.play().catch(() => {});
}

function updateTrack(direction = 0) {
    preferences.track = (preferences.track + direction + tracks.length) % tracks.length;
    trackNameElement.textContent = tracks[preferences.track].name;
    savePreferences();
    startMusic();
}

function updateVolume(value, persist = true) {
    preferences.volume = Math.max(0, Math.min(100, Number(value) || 0));
    volumeInput.value = preferences.volume;
    volumeInput.style.setProperty('--range-progress', `${preferences.volume}%`);
    volumeValue.textContent = `${preferences.volume}%`;
    musicPlayer.volume = preferences.volume / 100;
    if (persist) savePreferences();
}

function updateInterfaceSize(value, persist = true) {
    preferences.uiScale = Math.max(85, Math.min(120, Number(value) || 106));
    const progress = ((preferences.uiScale - 85) / (120 - 85)) * 100;
    document.documentElement.style.fontSize = `${preferences.uiScale}%`;
    interfaceSizeInput.value = preferences.uiScale;
    interfaceSizeInput.style.setProperty('--range-progress', `${progress}%`);
    interfaceSizeValue.textContent = `${preferences.uiScale}%`;
    if (persist) savePreferences();
}

function optionForId(options, id, fallbackId) {
    return options.find((option) => option.id === id)
        || options.find((option) => option.id === fallbackId)
        || options[0];
}

function scenePreferencesPayload() {
    return {
        backgroundId: preferences.backgroundId,
        animationId: preferences.animationId,
        time: preferences.time,
        weatherId: preferences.weatherId
    };
}

function formatSceneTime(value) {
    const minutes = Math.max(0, Math.min(1439, Number(value) || 0));
    const hour = Math.floor(minutes / 60);
    const minute = minutes % 60;
    const timeFormat = String(sceneOptions.timeFormat).toUpperCase();
    if (timeFormat === '12HR') {
        const suffix = hour >= 12 ? 'PM' : 'AM';
        const displayHour = hour % 12 || 12;
        return `${displayHour}:${String(minute).padStart(2, '0')} ${suffix}`;
    }
    return `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`;
}

function scheduleSceneUpdate(immediate = false) {
    savePreferences();
    if (isBrowserPreview) return;
    if (scenePostTimer) window.clearTimeout(scenePostTimer);
    scenePostTimer = window.setTimeout(() => post('backgroundSettings', scenePreferencesPayload()), immediate ? 0 : 70);
}

function renderSceneControls() {
    const defaults = sceneOptions.defaults || {};
    const background = optionForId(sceneOptions.backgrounds, preferences.backgroundId, defaults.backgroundId);
    const animation = optionForId(sceneOptions.animations, preferences.animationId, defaults.animationId);
    const weather = optionForId(sceneOptions.weather, preferences.weatherId, defaults.weatherId);
    if (!background || !animation || !weather) return;

    preferences.backgroundId = background.id;
    preferences.animationId = animation.id;
    preferences.weatherId = weather.id;
    preferences.time = Math.max(0, Math.min(1439, Number(preferences.time) || Number(defaults.time) || 720));

    backgroundNameElement.textContent = background.label;
    animationNameElement.textContent = translatedOptionLabel('animation', animation);
    sceneTimeInput.value = preferences.time;
    sceneTimeInput.style.setProperty('--range-progress', `${(preferences.time / 1439) * 100}%`);
    sceneTimeValue.textContent = formatSceneTime(preferences.time);

    sceneWeatherValue.textContent = translatedOptionLabel('weather', weather);

    const timeEnabled = sceneOptions.timeSettingsEnabled !== false;
    const weatherEnabled = sceneOptions.weatherSettingsEnabled !== false;
    timeSettingControl.classList.toggle('is-disabled', !timeEnabled);
    timeSettingLabel.classList.toggle('is-locked', !timeEnabled);
    timeSettingControl.setAttribute('aria-disabled', String(!timeEnabled));
    sceneTimeInput.disabled = !timeEnabled;
    weatherSettingControl.classList.toggle('is-disabled', !weatherEnabled);
    weatherSettingLabel.classList.toggle('is-locked', !weatherEnabled);
    weatherSettingControl.setAttribute('aria-disabled', String(!weatherEnabled));
    previousWeatherButton.disabled = !weatherEnabled;
    nextWeatherButton.disabled = !weatherEnabled;
}

function cycleSceneOption(optionKey, preferenceKey, direction) {
    if (optionKey === 'weather' && sceneOptions.weatherSettingsEnabled === false) return;
    const options = sceneOptions[optionKey];
    if (!Array.isArray(options) || !options.length) return;
    const currentIndex = Math.max(0, options.findIndex((option) => option.id === preferences[preferenceKey]));
    const nextIndex = (currentIndex + direction + options.length) % options.length;
    preferences[preferenceKey] = options[nextIndex].id;
    renderSceneControls();
    scheduleSceneUpdate(true);
}

function renderCustomThemeControls() {
    Object.keys(defaultCustomTheme).forEach((key) => {
        const color = normalizeHexColor(preferences[key], defaultCustomTheme[key]);
        preferences[key] = color;

        const picker = document.querySelector(`[data-color-picker="${key}"]`);
        if (picker) picker.value = color.toLowerCase();

        const rgb = hexToRgb(color);
        document.querySelectorAll(`[data-color-key="${key}"]`).forEach((input) => {
            input.value = rgb[input.dataset.colorChannel];
        });
    });

    const preview = document.querySelector('.theme-option__preview--custom');
    if (preview) {
        preview.style.background = `linear-gradient(135deg, ${preferences.customUiColor} 0 50%, ${preferences.customSettingsBackground} 50% 100%)`;
    }
}

function applyCustomThemeVariables() {
    const uiColor = normalizeHexColor(preferences.customUiColor, defaultCustomTheme.customUiColor);
    const settingsBackground = normalizeHexColor(preferences.customSettingsBackground, defaultCustomTheme.customSettingsBackground);
    const settingsText = normalizeHexColor(preferences.customSettingsText, defaultCustomTheme.customSettingsText);

    app.style.setProperty('--ui-color', uiColor);
    app.style.setProperty('--ui-soft', colorWithAlpha(uiColor, .72));
    app.style.setProperty('--ui-control', colorWithAlpha(uiColor, .82));
    app.style.setProperty('--ui-control-text', contrastingTextColor(uiColor));
    app.style.setProperty('--settings-bg', settingsBackground);
    app.style.setProperty('--settings-text', settingsText);
    app.style.setProperty('--settings-muted', colorWithAlpha(settingsText, .58));
    app.style.setProperty('--settings-line', colorWithAlpha(settingsText, .16));
}

function clearCustomThemeVariables() {
    [
        '--ui-color', '--ui-soft', '--ui-control', '--ui-control-text',
        '--settings-bg', '--settings-text', '--settings-muted', '--settings-line'
    ].forEach((property) => app.style.removeProperty(property));
}

function applyTheme(theme, persist = true) {
    preferences.theme = ['light', 'dark', 'custom'].includes(theme) ? theme : 'light';
    app.dataset.theme = preferences.theme;
    if (preferences.theme === 'custom') applyCustomThemeVariables();
    else clearCustomThemeVariables();

    renderCustomThemeControls();
    customThemeControls.classList.toggle('is-visible', preferences.theme === 'custom');
    customThemeControls.setAttribute('aria-hidden', String(preferences.theme !== 'custom'));
    document.querySelectorAll('[data-theme-value]').forEach((button) => {
        button.classList.toggle('is-active', button.dataset.themeValue === preferences.theme);
    });
    if (persist) savePreferences();
}

function setSettingsOpen(open) {
    settingsOpen = open;
    settingsPanel.classList.toggle('is-visible', open);
    settingsPanel.setAttribute('aria-hidden', String(!open));
}

function stopDeleteCountdown() {
    if (deleteCountdownTimer !== null) {
        window.clearInterval(deleteCountdownTimer);
        deleteCountdownTimer = null;
    }
    deleteCountdownDeadline = 0;
    confirmDeleteButton.classList.remove('is-counting');
}

function startDeleteCountdown() {
    stopDeleteCountdown();
    deleteCountdownReady = false;
    deleteCountdownDeadline = Date.now() + deleteConfirmationDelay;
    confirmDeleteButton.disabled = true;
    confirmDeleteButton.classList.add('is-counting');

    const updateCountdown = () => {
        const secondsRemaining = Math.max(0, Math.ceil((deleteCountdownDeadline - Date.now()) / 1000));
        if (secondsRemaining > 0) {
            confirmDeleteLabel.textContent = t('delete_in', { seconds: secondsRemaining });
            return;
        }

        stopDeleteCountdown();
        deleteCountdownReady = true;
        confirmDeleteLabel.textContent = t('delete_character');
        confirmDeleteButton.disabled = deletionBusy;
    };

    updateCountdown();
    deleteCountdownTimer = window.setInterval(updateCountdown, 250);
}

function closeDeleteConfirmation(resetBusy = true) {
    stopDeleteCountdown();
    if (deleteRequestTimer !== null) {
        window.clearTimeout(deleteRequestTimer);
        deleteRequestTimer = null;
    }
    deleteCountdownReady = false;
    deleteConfirmationOpen = false;
    pendingDeleteSlot = null;
    deleteConfirmation.classList.remove('is-visible');
    deleteConfirmation.setAttribute('aria-hidden', 'true');

    if (resetBusy) {
        deletionBusy = false;
        cancelDeleteButton.disabled = false;
        confirmDeleteButton.disabled = false;
        confirmDeleteLabel.textContent = t('delete_character');
    }
}

function openDeleteConfirmation() {
    const character = characters[selectedIndex];
    const canDelete = Boolean(slotConfig.canDelete)
        && character
        && !character.locked
        && !character.empty
        && !character.disabled;
    if (!canDelete || deletionBusy) return;

    resetParallax();
    pendingDeleteSlot = Number(character.slot) || selectedIndex + 1;
    deleteConfirmationTitle.textContent = t('delete_character_question', { name: characterName(character) });
    deleteConfirmationOpen = true;
    deleteConfirmation.classList.add('is-visible');
    deleteConfirmation.setAttribute('aria-hidden', 'false');
    startDeleteCountdown();
    window.setTimeout(() => cancelDeleteButton.focus(), 120);
}

function showStatusToast(message, title = null) {
    statusToastTitle.textContent = title || t('notice');
    statusToastMessage.textContent = message;
    statusToast.classList.remove('is-visible');
    void statusToast.offsetWidth;
    statusToast.classList.add('is-visible');
}

document.addEventListener('click', (event) => {
    if (event.target.closest('button')) playSoftClick();
});

document.addEventListener('pointermove', updateParallax);
document.addEventListener('mouseout', (event) => {
    if (!event.relatedTarget) resetParallax();
});
window.addEventListener('blur', () => resetParallax());
if (typeof reducedMotionQuery.addEventListener === 'function') {
    reducedMotionQuery.addEventListener('change', () => resetParallax(true));
}

document.querySelectorAll('button').forEach((button) => {
    button.addEventListener('pointerenter', () => {
        if (!button.disabled && !button.classList.contains('is-disabled')) playHoverSound();
    });
});

characterActions.addEventListener('animationend', (event) => {
    if (event.animationName === 'selection-play-out' && app.classList.contains('is-selecting')) {
        app.classList.add('is-play-finishing');
    }
});

document.querySelector('#previous').addEventListener('click', () => changeCharacter(-1));
document.querySelector('#next').addEventListener('click', () => changeCharacter(1));
actionButton.addEventListener('click', () => {
    if (app.classList.contains('is-selecting')) return;
    flushRemotePreferences();
    const character = characters[selectedIndex];
    if (character?.locked) {
        const slot = character.slot || selectedIndex + 1;
        if (!openStoreUrl()) return;
        if (isBrowserPreview) showStatusToast(t('store_link_opened'), t('paid_slot_test'));
        else post('buySlot', { slot });
        return;
    }
    if (character?.disabled) {
        showStatusToast(t('character_is_disabled'));
        return;
    }
    if (character?.empty) {
        const slot = character.slot || selectedIndex + 1;
        if (isBrowserPreview) {
            showStatusToast(t('create_slot_callback', { slot: String(slot).padStart(2, '0') }), t('preview_test'));
        } else {
            post('createCharacter', { slot, character });
        }
        return;
    }
    if (character) {
        if (isBrowserPreview) {
            resetParallax(true);
            app.classList.add('is-selecting');
            window.setTimeout(() => app.classList.remove('is-selecting', 'is-play-finishing'), 4000);
        } else {
            post('selectCharacter', { character, index: selectedIndex + 1 });
        }
    }
});
deleteCharacterButton.addEventListener('click', openDeleteConfirmation);
cancelDeleteButton.addEventListener('click', () => {
    if (!deletionBusy) closeDeleteConfirmation();
});
deleteConfirmation.addEventListener('click', (event) => {
    if (event.target === deleteConfirmation && !deletionBusy) closeDeleteConfirmation();
});
confirmDeleteButton.addEventListener('click', () => {
    const character = characters[selectedIndex];
    const slot = Number(character?.slot) || selectedIndex + 1;
    const validTarget = deleteConfirmationOpen
        && pendingDeleteSlot === slot
        && Boolean(slotConfig.canDelete)
        && character
        && !character.locked
        && !character.empty
        && !character.disabled;
    if (!validTarget || deletionBusy || !deleteCountdownReady) return;

    deletionBusy = true;
    deleteCountdownReady = false;
    stopDeleteCountdown();
    cancelDeleteButton.disabled = true;
    confirmDeleteButton.disabled = true;
    deleteCharacterButton.disabled = true;
    confirmDeleteLabel.textContent = t('deleting');

    if (isBrowserPreview) {
        window.setTimeout(() => {
            characters[selectedIndex] = { slot, empty: true, locked: false };
            closeDeleteConfirmation();
            render();
            showStatusToast(t('slot_now_empty', { slot: String(slot).padStart(2, '0') }), t('character_deleted'));
        }, 650);
        return;
    }

    post('deleteCharacter', { slot });
    deleteRequestTimer = window.setTimeout(() => {
        if (!deletionBusy) return;
        closeDeleteConfirmation();
        showStatusToast(t('character_deletion_failed'), t('delete_failed'));
    }, 20000);
});
document.querySelector('#open-settings').addEventListener('click', () => setSettingsOpen(true));
document.querySelector('#close-settings').addEventListener('click', () => setSettingsOpen(false));
document.querySelector('#previous-track').addEventListener('click', () => updateTrack(-1));
document.querySelector('#next-track').addEventListener('click', () => updateTrack(1));
previousLocaleButton.addEventListener('click', () => cycleLocale(-1));
nextLocaleButton.addEventListener('click', () => cycleLocale(1));
document.addEventListener('pointerdown', () => {
    if (musicPlayer.src && musicPlayer.paused) musicPlayer.play().catch(() => {});
}, { capture: true });
document.querySelector('#previous-background').addEventListener('click', () => cycleSceneOption('backgrounds', 'backgroundId', -1));
document.querySelector('#next-background').addEventListener('click', () => cycleSceneOption('backgrounds', 'backgroundId', 1));
document.querySelector('#previous-animation').addEventListener('click', () => cycleSceneOption('animations', 'animationId', -1));
document.querySelector('#next-animation').addEventListener('click', () => cycleSceneOption('animations', 'animationId', 1));
previousWeatherButton.addEventListener('click', () => cycleSceneOption('weather', 'weatherId', -1));
nextWeatherButton.addEventListener('click', () => cycleSceneOption('weather', 'weatherId', 1));

document.querySelectorAll('[data-settings-tab]').forEach((button) => {
    button.addEventListener('click', () => {
        document.querySelectorAll('[data-settings-tab]').forEach((tab) => tab.classList.toggle('is-active', tab === button));
        document.querySelectorAll('.settings-page').forEach((page) => page.classList.toggle('is-active', page.id === `${button.dataset.settingsTab}-settings`));
    });
});

document.querySelectorAll('[data-theme-value]').forEach((button) => {
    button.addEventListener('click', () => applyTheme(button.dataset.themeValue));
});

document.querySelectorAll('[data-color-picker]').forEach((picker) => {
    picker.addEventListener('input', () => {
        const key = picker.dataset.colorPicker;
        if (!Object.prototype.hasOwnProperty.call(defaultCustomTheme, key)) return;
        preferences[key] = normalizeHexColor(picker.value, defaultCustomTheme[key]);
        applyTheme('custom');
    });
    picker.addEventListener('change', playSoftClick);
});

document.querySelectorAll('[data-color-channel]').forEach((input) => {
    input.addEventListener('input', () => {
        const key = input.dataset.colorKey;
        const channel = input.dataset.colorChannel;
        if (!Object.prototype.hasOwnProperty.call(defaultCustomTheme, key) || !['r', 'g', 'b'].includes(channel)) return;

        const rgb = hexToRgb(preferences[key]);
        rgb[channel] = Math.max(0, Math.min(255, Number(input.value) || 0));
        preferences[key] = rgbToHex(rgb);
        applyTheme('custom');
    });
    input.addEventListener('change', playSoftClick);
});

resetCustomThemeButton.addEventListener('click', () => {
    Object.assign(preferences, defaultCustomTheme);
    applyTheme('custom');
});

volumeInput.addEventListener('input', () => updateVolume(volumeInput.value));
volumeInput.addEventListener('change', playSoftClick);
interfaceSizeInput.addEventListener('input', () => updateInterfaceSize(interfaceSizeInput.value));
interfaceSizeInput.addEventListener('change', playSoftClick);
sceneTimeInput.addEventListener('input', () => {
    if (sceneOptions.timeSettingsEnabled === false) return;
    preferences.time = Math.max(0, Math.min(1439, Number(sceneTimeInput.value) || 0));
    renderSceneControls();
    scheduleSceneUpdate();
});
sceneTimeInput.addEventListener('change', playSoftClick);

window.addEventListener('keydown', (event) => {
    if (!app.classList.contains('is-visible')) return;
    if (app.classList.contains('is-selecting')) return;
    if (deleteConfirmationOpen) {
        if (event.key === 'Escape' && !deletionBusy) {
            playSoftClick();
            closeDeleteConfirmation();
        }
        return;
    }
    if (settingsOpen) {
        if (event.key === 'Escape') {
            playSoftClick();
            setSettingsOpen(false);
        }
        return;
    }
    if (event.key === 'ArrowLeft') { playSoftClick(); changeCharacter(-1); }
    if (event.key === 'ArrowRight') { playSoftClick(); changeCharacter(1); }
    if (event.key === 'Enter') document.querySelector('#play').click();
    if (event.key === 'Escape') { flushRemotePreferences(); post('close'); }
});

window.addEventListener('message', ({ data }) => {
    if (data.action === 'open') {
        resetParallax(true);
        app.classList.remove('is-selecting', 'is-play-finishing');
        closeDeleteConfirmation();
        remotePreferencesReady = false;
        configureLocales(data.localeOptions);
        if (data.sceneOptions && typeof data.sceneOptions === 'object') {
            sceneOptions = {
                ...sceneOptions,
                ...data.sceneOptions,
                defaults: { ...sceneOptions.defaults, ...(data.sceneOptions.defaults || {}) }
            };
        }
        applyStoredPreferences(data.preferences);
        tracks = buildMusicTracks(data.musicTracks);
        preferences.track = normalizeTrackIndex(preferences.track);
        trackNameElement.textContent = tracks[preferences.track].name;
        applyTheme(preferences.theme, false);
        updateVolume(preferences.volume, false);
        updateInterfaceSize(preferences.uiScale, false);
        slotConfig = data.slotConfig && typeof data.slotConfig === 'object' ? data.slotConfig : { enabled: false };
        characters = buildCharacterSlots(data.characters, slotConfig);
        selectedIndex = Math.max(0, Math.min((Number(data.selectedIndex) || 1) - 1, characters.length - 1));
        applyLocale(preferences.locale, false);
        app.classList.add('is-visible');
        app.setAttribute('aria-hidden', 'false');
        remotePreferencesReady = true;
        startMusic();
        scheduleSceneUpdate(true);
    }
    if (data.action === 'selectionCinematic') {
        resetParallax(true);
        setSettingsOpen(false);
        app.classList.add('is-selecting');
    }
    if (data.action === 'selectionFailed') {
        app.classList.remove('is-selecting', 'is-play-finishing');
        app.classList.add('is-visible');
        app.setAttribute('aria-hidden', 'false');
        showStatusToast(data.message || t('selection_request_failed'), t('notice'));
    }
    if (data.action === 'close') {
        resetParallax(true);
        flushRemotePreferences();
        remotePreferencesReady = false;
        setSettingsOpen(false);
        closeDeleteConfirmation();
        stopMusic();
        app.classList.remove('is-selecting', 'is-play-finishing');
        app.classList.remove('is-visible');
        app.setAttribute('aria-hidden', 'true');
    }
    if (data.action === 'purchaseStatus' || data.action === 'notify') {
        showStatusToast(data.message || t('request_received'), data.action === 'purchaseStatus' ? t('slot_purchase') : t('notice'));
    }
    if (data.action === 'deleteStatus') {
        const succeeded = data.success === true;
        closeDeleteConfirmation();
        showStatusToast(
            data.message || t(succeeded ? 'character_deleted' : 'character_deletion_failed'),
            t(succeeded ? 'character_deleted' : 'delete_failed')
        );
    }
});

trackNameElement.textContent = tracks[0].name;
applyTheme(preferences.theme, false);
updateVolume(preferences.volume, false);
updateInterfaceSize(preferences.uiScale, false);
applyLocale(preferences.locale, false);

// Browser preview outside FiveM.
if (isBrowserPreview) {
    const previewSlot = Math.max(1, Math.min(3, Number(new URLSearchParams(window.location.search).get('slot')) || 1));
    window.postMessage({
        action: 'open', selectedIndex: previewSlot,
        slotConfig: {
            enabled: true,
            canDelete: true,
            freeSlots: 2,
            totalSlots: 3,
            purchasedSlots: 0,
            priceLabel: 'PAID CHARACTER SLOT',
            storeEnabled: true,
            storeUrl: 'https://example.com/'
        },
        musicTracks: [
            { name: 'DREAM AMBIENCE', file: 'music/dream-ambience.mp3' },
            { name: 'CONTEMPLATION', file: 'music/contemplation.mp3' }
        ],
        characters: [
            { slot: 1, firstname: 'Adrian', lastname: 'Moretti', jobName: 'police', jobGradeLabel: 'Lieutenant', lastPlayed: '2026-08-19T21:42:00Z' },
            { slot: 2, firstname: 'Elijah', lastname: 'Bennett', jobName: 'ambulance', jobGradeLabel: 'Doctor', lastPlayed: '2026-08-16T14:18:00Z' }
        ]
    }, '*');
} else {
    post('nuiReady', { scenePreferences: scenePreferencesPayload() });
}
