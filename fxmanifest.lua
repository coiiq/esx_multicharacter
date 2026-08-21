fx_version 'cerulean'
game 'gta5'

author 'COII'
description 'ESX Legacy multicharacter with paid-slot support'
version '2.0.0'
lua54 'yes'

dependencies {
    'es_extended',
    'oxmysql',
    'esx_identity',
    'skinchanger',
    'esx_skin'
}

shared_scripts {
    '@es_extended/imports.lua',
    'config.lua',
    'locales.lua'
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
    'html/music/*.mp3'
}

client_script 'client/client.lua'

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}
