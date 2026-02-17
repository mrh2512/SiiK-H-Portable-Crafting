fx_version 'cerulean'
game 'gta5'

author 'SiiK Scripts'
description 'SiiK-H-portable-crafting (FULL) Items+Weapons, Blueprint NUI, XP/Levels, Persistence, Anti-Dupe'
version '1.5.0'

ui_page 'html/index.html'

files {
  'html/index.html',
  'html/style.css',
  'html/app.js'
}

shared_scripts {
  '@qb-core/shared/locale.lua',
  'config.lua',
  'shared/recipes.lua'
}

client_scripts {
  'client/main.lua'
}

server_scripts {
  '@oxmysql/lib/MySQL.lua',
  'server/xp.lua',
  'server/inventory.lua',
  'server/main.lua'
}

lua54 'yes'
