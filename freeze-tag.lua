-- name: Freeze Tag
-- incompatible: gamemode
-- description: A simple Freeze Tag gamemode, best playable with 4 or more players.\n\nRULES:\n\nEvery round, "It" is chosen at random. They are shown with METAL Mario colors. "It" must tag Runners before time runs out.\n\nWhen "It" tags a Runner, they are frozen and cannot move. Only other Runners can unfreeze Runners.\n\nWhen all Runners are frozen, "It" wins. If time runs out, the Runners win! SURVIVE until time runs out!!!\n\nMade by sm64rise | version 2

gGlobalSyncTable.freezeTag = true

ROUND_STATE_WAIT = 0
ROUND_STATE_ACTIVE = 1
ROUND_STATE_TAGGERS_WIN = 2
ROUND_STATE_RUNNERS_WIN = 3
ROUND_STATE_UNKNOWN_END = 4

gGlobalSyncTable.roundState = ROUND_STATE_WAIT

gGlobalSyncTable.displayTimer = 0
gGlobalSyncTable.roundEndTimeout = 6 * 60 * 30
sRoundTimer = 0
sRoundStartTimeout  = 15 * 30       -- 15 seconds
gGlobalSyncTable.roundEndTimeout    = 6 * 60 * 30   -- 6 minutes

-- Camping Detection
gGlobalSyncTable.campingDetection = true
sLastPos = {}
sLastPos.x = 0
sLastPos.y = 0
sLastPos.z = 0
sDistanceMoved = 0
sDistanceTimer = 0
sDistanceTimeout = 15 * 30 -- 15 seconds

sFlashingIndex = 0

function server_update(m)
    -- Timer
    sRoundTimer = sRoundTimer + 1
    gGlobalSyncTable.displayTimer = math.floor(sRoundTimer / 30)

    -- Game state
    local hasTagger = false
    local hasRunner = false
    local activePlayers = {}
    local connectedCount = 0

    for i = 0, (MAX_PLAYERS - 1) do
        if gNetworkPlayers[i].connected then
            connectedCount = connectedCount + 1
            table.insert(activePlayers, gPlayerSyncTable[i])
            if gPlayerSyncTable[i].tagger or gPlayerSyncTable[i].frozen then
                hasTagger = true
            else
                hasRunner = true
            end
        end
    end

    -- Only start if 3 or more players
    if (connectedCount < 3) then
        gGlobalSyncTable.roundState = ROUND_STATE_WAIT
        return
    elseif gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
        gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
        sRoundTimer = 0
        gGlobalSyncTable.displayTimer = 0
    end

    -- End round
    if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        if not hasRunner or not hasTagger or sRoundTimer > gGlobalSyncTable.roundEndTimeout then
            if not hasRunner then
                gGlobalSyncTable.roundState = ROUND_STATE_TAGGERS_WIN
            elseif sRoundTimer > gGlobalSyncTable.roundEndTimeout then
                gGlobalSyncTable.roundState = ROUND_STATE_RUNNERS_WIN
            else
                gGlobalSyncTable.roundState = ROUND_STATE_UNKNOWN_END
            end
            sRoundTimer = 0
            gGlobalSyncTable.displayTimer = 0
        else
            return
        end
    end

    -- Start round
    if sRoundTimer >= sRoundStartTimeout then
        -- Reset taggers and frozen runners
        for i = 0, (MAX_PLAYERS - 1) do
            gPlayerSyncTable[i].tagger = false
            gPlayerSyncTable[i].frozen = false
        end
        hasTagger = false

        -- Pick a random tagger
        local t = activePlayers[math.random(#activePlayers)]
        t.tagger = true

        -- To balance things out, we may add more taggers
        if (connectedCount > 5) then
            local t1 = activePlayers[math.random(#activePlayers)]
            while t1 == t do
                t1 = activePlayers[math.random(#activePlayers)]
            end
            t1.tagger = true
            if (connectedCount > 8) then
                local t2 = activePlayers[math.random(#activePlayers)]
                while t2 == t1 or t2 == t do
                    t2 = activePlayers[math.random(#activePlayers)]
                end
                t2.tagger = true
            end
        end

        -- Set round state
        gGlobalSyncTable.roundState = ROUND_STATE_ACTIVE
        sRoundTimer = 0
        gGlobalSyncTable.roundEndTimeout = connectedCount * 60 * 30
        djui_chat_message_create('Good luck! You have ' .. connectedCount .. ' minutes...')
        gGlobalSyncTable.displayTimer = 0
    end
end

function camping_detection(m)
    -- This code only runs for the local player
    local s = gPlayerSyncTable[m.playerIndex]

    -- Track how far the local player has moved recently
    sDistanceMoved = sDistanceMoved - 0.25 + vec3f_dist(sLastPos, m.pos) * 0.02
    vec3f_copy(sLastPos, m.pos)

    -- Clamp between 0 to 100
    if sDistanceMoved < 0   then sDistanceMoved = 0   end
    if sDistanceMoved > 100 then sDistanceMoved = 100 end

    -- If player hasn't moved enough, start a timer
    if sDistanceMoved < 10 and not s.tagger and not s.frozen then
        sDistanceTimer = sDistanceTimer + 1
    end

    -- If the player has moved enough, reset the timer
    if sDistanceMoved > 25 then
        sDistanceTimer = 0
    end

    -- If the player becomes frozen, reset the timer
    if s.frozen then
        sDistanceTimer = 0
    end

    -- Inform the player that they need to move, or freeze them
    if sDistanceTimer > sDistanceTimeout then
        s.frozen = true
    end

    -- Make sound
    if sDistanceTimer > 0 and sDistanceTimer % 30 == 1 then
        play_sound(SOUND_MENU_CAMERA_BUZZ, m.marioObj.header.gfx.cameraToObject)
    end
end

function update()
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.freezeTag then
        return
    end

    -- Only the server should demand a tagger
    if network_is_server() then
        server_update(gMarioStates[0])
    end

    -- Check if local player is camping
    if gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE and gGlobalSyncTable.campingDetection then
        camping_detection(gMarioStates[0])
    else
        sDistanceTimer = 0
    end
end

function mario_update(m)
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.freezeTag then
        return
    end

    -- This code runs for all players
    local p = gPlayerSyncTable[m.playerIndex]

    -- If the local player died, make them a taggr
    if m.playerIndex == 0 and m.health <= 0x110 then
        p.tagger = true
    end

    -- Display all taggers as METAL
    if p.tagger then
        m.marioBodyState.modelState = MODEL_STATE_METAL
        m.health = 0x880
    end

    -- Freeze tagged players
    if not p.tagger and p.frozen then
        set_mario_action(m, ACT_SHIVERING, 0)
        m.marioBodyState.modelState = MODEL_STATE_NOISE_ALPHA
        m.health = 0x880
        vec3f_copy(m.marioObj.header.gfx.pos, m.pos)
        vec3s_set(m.marioObj.header.gfx.angle, -m.faceAngle.x, m.faceAngle.y, m.faceAngle.z)
    end
end

function mario_before_phys_step(m)
    -- Prevent physics from being altered when bubbled
    if m.action == ACT_BUBBLED then
        return
    end

    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.freezeTag then
        return
    end

    local p = gPlayerSyncTable[m.playerIndex]

    -- Only make taggers faster
    if not p.tagger then
        return
    end

    local hScale = 1.0
    local vScale = 1.0

    -- Make swimming taggers 5% faster
    if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
        hScale = hScale * 1.05
        if m.action ~= ACT_WATER_PLUNGE then
            vScale = vScale * 1.05
        end
    end

    -- Faster ground movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 1.3
        m.marioBodyState.handState = MARIO_HAND_OPEN
    end

    m.vel.x = m.vel.x * hScale
    m.vel.y = m.vel.y * vScale
    m.vel.z = m.vel.z * hScale
end

function on_pvp_attack(attacker, victim)
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.freezeTag then
        return
    end

    -- This code runs when a player attacks another player
    local sAttacker = gPlayerSyncTable[attacker.playerIndex]
    local sVictim = gPlayerSyncTable[victim.playerIndex]

    -- Only consider local player
    if victim.playerIndex ~= 0 then
        return
    end

    -- Tag runners
    if not sVictim.tagger then
        if sAttacker.tagger and not sVictim.frozen then
            sVictim.frozen = true
            set_mario_action(victim, ACT_SHIVERING, 0)
        elseif sVictim.frozen and not sAttacker.tagger then
            sVictim.frozen = false
            set_mario_action(victim, ACT_IDLE, 0)
        end
    end
end

function on_player_connected(m)
    -- Start out as a non-tagger
    local p = gPlayerSyncTable[m.playerIndex]
    p.tagger = false
    network_player_set_description(gNetworkPlayers[m.playerIndex], "Runner", 64, 64, 64, 255)
end

-- HUD

function hud_top_render()
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.freezeTag then
        return
    end

    local seconds = 0
    local text = ''

    if gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
        seconds = 60
        text = 'Waiting for Players'
    elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        seconds = math.floor(gGlobalSyncTable.roundEndTimeout / 30 - gGlobalSyncTable.displayTimer)
        if seconds < 0 then seconds = 0 end
        text = seconds .. ' Seconds Remain'
    else
        seconds = math.floor(sRoundStartTimeout / 30 - gGlobalSyncTable.displayTimer)
        if seconds < 0 then seconds = 0 end
        text = 'Next Round in ' .. seconds .. ' Seconds'
    end

    local scale = 0.50

    -- Get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local width = djui_hud_measure_text(text) * scale

    local x = (screenWidth - width) / 2.0
    local y = 0

    local background = 0.0
    if seconds < 60 and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        background = (math.sin(sFlashingIndex / 10.0) * 0.5 + 0.5) * 1.0
        background = background * background
        background = background * background
    end

    -- Render top
    djui_hud_set_color(255 * background, 0, 0, 128);
    djui_hud_render_rect(x - 6, y, width + 12, 16);

    djui_hud_set_color(255, 255, 255, 255);
    djui_hud_print_text(text, x, y, scale);
end

function hud_bottom_render()
    local seconds = math.floor((sDistanceTimeout - sDistanceTimer) / 30)
    if seconds < 0 then seconds = 0 end
    if sDistanceTimer < 1 then return end

    local text = 'Keep moving! (' .. seconds .. ')'
    local scale = 0.50

    -- Get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()
    local width = djui_hud_measure_text(text) * scale

    local x = (screenWidth - width) / 2.0
    local y = screenHeight - 16

    local background = (math.sin(sFlashingIndex / 10.0) * 0.5 + 0.5) * 1.0
    background = background * background
    background = background * background

    -- Render top
    djui_hud_set_color(255 * background, 0, 0, 128);
    djui_hud_render_rect(x - 6, y, width + 12, 16);

    djui_hud_set_color(255, 255, 255, 255);
    djui_hud_print_text(text, x, y, scale);
end

function hud_center_render()
    if gGlobalSyncTable.displayTimer > 3 then return end

    -- Set text
    local text = ''
    if gGlobalSyncTable.roundState == ROUND_STATE_TAGGERS_WIN then
        text = '"It" Wins!'
    elseif gGlobalSyncTable.roundState == ROUND_STATE_RUNNERS_WIN then
        text = 'Runners Win!'
    elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        text = 'Go!'
    else
        return
    end

    -- Set scale
    local scale = 1

    -- Get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local screenHeight = djui_hud_get_screen_height()
    local width = djui_hud_measure_text(text) * scale
    local height = 32 * scale

    local x = (screenWidth - width) / 2.0
    local y = (screenHeight - height) / 2.0

    -- Render
    djui_hud_set_color(0, 0, 0, 128);
    djui_hud_render_rect(x - 6 * scale, y, width + 12 * scale, height);

    djui_hud_set_color(255, 255, 255, 255);
    djui_hud_print_text(text, x, y, scale);
end

function on_hud_render()
    -- Render to N64 screen space, with the HUD font
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_NORMAL)

    hud_top_render()
    hud_bottom_render()
    hud_center_render()

    sFlashingIndex = sFlashingIndex + 1
end

-- Commands

function on_freeze_tag_command(msg)
    if not network_is_server() then
        djui_chat_message_create('Only the host can change this setting!')
        return true
    end
    if msg == 'on' then
        djui_chat_message_create('Freeze Tag: Enabled')
        gGlobalSyncTable.freezeTag = true
        return true
    elseif msg == 'off' then
        djui_chat_message_create('Freeze Tag: Disabled')
        gGlobalSyncTable.freezeTag = false
        return true
    end
    return false
end

function on_camping_detection_command(msg)
    if not network_is_server() then
        djui_chat_message_create('Only the host can change this setting!')
        return true
    end
    if msg == 'on' then
        djui_chat_message_create('Camping: Enabled')
        gGlobalSyncTable.campingDetection = true
        return true
    elseif msg == 'off' then
        djui_chat_message_create('Camping: Disabled')
        gGlobalSyncTable.campingDetection = false
        return true
    end
    return false
end

-----------------------
-- Network Callbacks --
-----------------------

function on_round_state_changed(tag, oldVal, newVal)
    local rs = gGlobalSyncTable.roundState

    if     rs == ROUND_STATE_WAIT        then
        -- nothing
    elseif rs == ROUND_STATE_ACTIVE      then
        play_character_sound(gMarioStates[0], CHAR_SOUND_HERE_WE_GO)
    elseif rs == ROUND_STATE_TAGGERS_WIN then
        play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
    elseif rs == ROUND_STATE_RUNNERS_WIN  then
        play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
    elseif rs == ROUND_STATE_UNKNOWN_END then
        -- nothing
    end
end

function on_tagger_changed(tag, oldVal, newVal)
    local m = gMarioStates[tag]
    local np = gNetworkPlayers[tag]
    local t = gPlayerSyncTable[tag]

    -- Play sound and create popup if became a tagger
    if newVal and not oldVal then
        play_sound(SOUND_OBJ_BOWSER_LAUGH, m.marioObj.header.gfx.cameraToObject)
        playerColor = network_get_player_text_color_string(m.playerIndex)
        djui_popup_create(playerColor .. np.name .. '\\#ffa0a0\\ is now "it"', 2)
        --sRoundTimer = 0
    end

    if newVal then
        network_player_set_description(np, "It", 255, 64, 64, 255)
    else
        network_player_set_description(np, "Runner", 128, 128, 128, 255)
    end
end

function on_frozen_changed(tag, oldVal, newVal)
    local m = gMarioStates[tag]
    local np = gNetworkPlayers[tag]
    local t = gPlayerSyncTable[tag]

    -- Play sound and create popup if runner becomes frozen
    if newVal and not oldVal then
        playerColor = network_get_player_text_color_string(m.playerIndex)
        djui_popup_create(playerColor .. np.name .. '\\#a0a0ff\\ was frozen', 2)
        --sRoundTimer = 0
    end

    if newVal then
        network_player_set_description(np, "Frozen", 64, 64, 255, 255)
    else
        network_player_set_description(np, "Runner", 128, 128, 128, 255)
    end
end

-----------
-- Hooks --
-----------

hook_event(HOOK_UPDATE, update)
hook_event(HOOK_MARIO_UPDATE, mario_update)
hook_event(HOOK_BEFORE_PHYS_STEP, mario_before_phys_step)
hook_event(HOOK_ON_PVP_ATTACK, on_pvp_attack)
hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)
hook_event(HOOK_ON_HUD_RENDER, on_hud_render)

hook_chat_command('freeze-tag', "[on|off] - Turn Freeze Tag on or off", on_freeze_tag_command)
hook_chat_command('camping', "[on|off] - Allows/disallows \"camping\" in Freeze Tag", on_camping_detection_command)

-- Call functions when certain sync table values change
hook_on_sync_table_change(gGlobalSyncTable, 'roundState', 0, on_round_state_changed)
for i = 0,(MAX_PLAYERS - 1) do
    gPlayerSyncTable[i].tagger = true
    hook_on_sync_table_change(gPlayerSyncTable[i], 'tagger', i, on_tagger_changed)
    hook_on_sync_table_change(gPlayerSyncTable[i], 'frozen', i, on_frozen_changed)
    network_player_set_description(gNetworkPlayers[i], "It", 255, 64, 64, 255)
end
