-- name: Infection
-- incompatible: gamemode
-- description: The apocalypse is taking over!!\n\n\RULES:\n\n- Every round, one or more zombies are chosen at random. Their goal is to kill survivors and spread the infection.\n- As a survivor, you must survive until the timer hits zero. If you die or pause-exit, you will be turned into a zombie.\n\nMade by sm64rise | version 1

gGlobalSyncTable.infection = true
gGlobalSyncTable.punish_warping = true

ROUND_STATE_WAIT = 0
ROUND_STATE_ACTIVE = 1
ROUND_STATE_ZOMBIES_WIN = 2
ROUND_STATE_SURVIVORS_WIN = 3
ROUND_STATE_UNKNOWN_END = 4

gGlobalSyncTable.roundState = ROUND_STATE_WAIT

gGlobalSyncTable.displayTimer = 0
gGlobalSyncTable.roundEndTimeout = 6 * 60 * 30
sRoundTimer = 0
sRoundStartTimeout  = 15 * 30       -- 15 seconds
gGlobalSyncTable.roundEndTimeout    = 6 * 60 * 30   -- 6 minutes

sFlashingIndex = 0

function server_update(m)
    -- Timer
    sRoundTimer = sRoundTimer + 1
    gGlobalSyncTable.displayTimer = math.floor(sRoundTimer / 30)

    -- Game state
    local hasZombie = false
    local hasSurvivor = false
    local activePlayers = {}
    local connectedCount = 0

    for i = 0, (MAX_PLAYERS - 1) do
        if gNetworkPlayers[i].connected then
            connectedCount = connectedCount + 1
            table.insert(activePlayers, gPlayerSyncTable[i])
            if gPlayerSyncTable[i].zombie then
                hasZombie = true
            else
                hasSurvivor = true
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
        if not hasSurvivor or not hasZombie or sRoundTimer > gGlobalSyncTable.roundEndTimeout then
            if not hasSurvivor then
                gGlobalSyncTable.roundState = ROUND_STATE_ZOMBIES_WIN
            elseif sRoundTimer > gGlobalSyncTable.roundEndTimeout then
                gGlobalSyncTable.roundState = ROUND_STATE_SURVIVORS_WIN
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
        -- Reset zombies
        for i = 0, (MAX_PLAYERS - 1) do
            gPlayerSyncTable[i].zombie = false
            gMarioStates[i].health = 0x880
        end
        hasZombie = false

        -- Pick a random zombie
        infect_random_survivor(activePlayers)

        -- To balance things out, we may add more zombies
        if connectedCount > 5 then
            for i = 0, (math.floor(connectedCount / 5) - 1) do
                infect_random_survivor(activePlayers)
            end
        end

        -- Set round state, scale the round duration with the amount of players connected
        gGlobalSyncTable.roundState = ROUND_STATE_ACTIVE
        sRoundTimer = 0
        gGlobalSyncTable.roundEndTimeout = connectedCount * 60 * 30
        gGlobalSyncTable.displayTimer = 0
    end
end

function update()
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.infection then
        return
    end

    -- Only the server should demand a zombie
    if network_is_server() then
        server_update(gMarioStates[0])
    end
end

function mario_update(m)
    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.infection then
        return
    end

    -- This code runs for all players
    local p = gPlayerSyncTable[m.playerIndex]

    -- If the local player died, make them a zombie
    if m.playerIndex == 0 and m.health <= 0x110 then
        p.zombie = true
    end

    -- Display all zombies as METAL
    if p.zombie then
        m.marioBodyState.modelState = MODEL_STATE_METAL
        m.marioBodyState.capState = MARIO_HAS_DEFAULT_CAP_OFF
    end

    -- All survivors have less health
    if not p.zombie then
        if m.health > 0x330 then m.health = 0x330 end
    end
end

function mario_before_phys_step(m)
    -- Prevent physics from being altered when bubbled
    if m.action == ACT_BUBBLED then
        return
    end

    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.infection then
        return
    end

    local p = gPlayerSyncTable[m.playerIndex]

    -- Only make zombies faster
    if not p.zombie then
        return
    end

    local hScale = 1.0
    local vScale = 1.0

    -- Make swimming zombies 50% faster
    if (m.action & ACT_FLAG_SWIMMING) ~= 0 then
        hScale = hScale * 1.5
        if m.action ~= ACT_WATER_PLUNGE then
            vScale = vScale * 1.5
        end
    end

    -- Faster ground movement
    if (m.action & ACT_FLAG_MOVING) ~= 0 then
        hScale = hScale * 1.25
        m.marioBodyState.handState = MARIO_HAND_OPEN
    end

    m.vel.x = m.vel.x * hScale
    m.vel.y = m.vel.y * vScale
    m.vel.z = m.vel.z * hScale
end

function infect_random_survivor(activePlayers)
    -- This function chooses a random survivor and infects them. Used when the round begins

    local r = activePlayers[math.random(#activePlayers)]
    if not r.zombie then
        r.zombie = true
        return
    else
        -- If the random player was already a zombie, reroll
        infect_random_survivor()
    end
end

function on_player_connected(m)
    -- New players will always be infected
    local p = gPlayerSyncTable[m.playerIndex]
    p.zombie = true
    network_player_set_description(gNetworkPlayers[m.playerIndex], "Zombie", 64, 255, 64, 255)

    -- Set server settings
    gServerSettings.playerInteractions = PLAYER_INTERACTIONS_PVP
    gServerSettings.bubbleDeath = 0
    gServerSettings.shareLives = 0
    gServerSettings.enableCheats = 0
end

function allow_pvp_attack(attacker, victim)
    local sAttacker = gPlayerSyncTable[attacker.playerIndex]
    local sVictim = gPlayerSyncTable[victim.playerIndex]

    -- Disallow "friendly fire" on team members
    if sAttacker.zombie and not sVictim.zombie then
        return true
    elseif sVictim.zombie and not sAttacker.zombie then
        return true
    else
        return false
    end
end

function on_pause_exit(exitToCastle)
    -- This code runs when the local player pause-exits the course
    local lp = gPlayerSyncTable[gMarioStates[0].playerIndex]

    -- Cancel if punish warping is disabled
    if not gGlobalSyncTable.punish_warping then
        return
    end

    if (lp.zombie == false) then
        lp.zombie = true
    end
end

---------
-- HUD --
---------

function on_hud_render()
    -- Render to N64 screen space, with the HUD font
    djui_hud_set_resolution(RESOLUTION_N64)
    djui_hud_set_font(FONT_NORMAL)

    -- Cancel if gamemode is disabled
    if not gGlobalSyncTable.infection then
        return
    end

    local minutes = 0
    local seconds = 0
    local total_seconds = 0

    local secondsColon = ":"
    local text = ''

    if gGlobalSyncTable.roundState == ROUND_STATE_WAIT then
        total_seconds = 60
        text = 'Waiting for Players'
    elseif gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        total_seconds = math.floor(gGlobalSyncTable.roundEndTimeout / 30 - gGlobalSyncTable.displayTimer)
        if total_seconds < 0 then total_seconds = 0 end
        minutes = math.floor((total_seconds) / 60);
        seconds = total_seconds - (minutes * 60);

        if (seconds < 10) then secondsColon = ":0" else secondsColon = ":" end
        text = minutes .. secondsColon .. seconds .. ' Left'
    else
        total_seconds = math.floor(sRoundStartTimeout / 30 - gGlobalSyncTable.displayTimer)
        if total_seconds < 0 then total_seconds = 0 end
        text = 'Next Round in ' .. total_seconds .. ' Seconds'
    end

    local scale = 0.50

    -- Get width of screen and text
    local screenWidth = djui_hud_get_screen_width()
    local width = djui_hud_measure_text(text) * scale

    local x = (screenWidth - width) / 2.0
    local y = 0

    local background = 0.0
    if total_seconds < 60 and gGlobalSyncTable.roundState == ROUND_STATE_ACTIVE then
        background = (math.sin(sFlashingIndex / 10.0) * 0.5 + 0.5) * 1.0
        background = background * background
        background = background * background
    end

    -- Render top
    djui_hud_set_color(255 * background, 0, 0, 128);
    djui_hud_render_rect(x - 6, y, width + 12, 16);

    djui_hud_set_color(255, 255, 255, 255);
    djui_hud_print_text(text, x, y, scale);

    sFlashingIndex = sFlashingIndex + 1
end

-----------------------
-- Network Callbacks --
-----------------------

function on_round_state_changed(tag, oldVal, newVal)
    local rs = gGlobalSyncTable.roundState
    local lp = gPlayerSyncTable[gMarioStates[0].playerIndex]

    if rs == ROUND_STATE_ACTIVE and gGlobalSyncTable.displayTimer == 15 then
        if lp.zombie then
            play_character_sound(gMarioStates[0], CHAR_SOUND_DROWNING)
            djui_chat_message_create('\\#a0ffa0\\Infect them all. ')
        else
            play_character_sound(gMarioStates[0], CHAR_SOUND_COUGHING1)
            djui_chat_message_create('The infection has begun to spread...')
        end
    elseif rs == ROUND_STATE_ZOMBIES_WIN then
        play_sound(SOUND_OBJ_BOO_LAUGH_SHORT, gMarioStates[0].marioObj.header.gfx.cameraToObject)
        djui_chat_message_create('\\#a0ffa0\\The infection has won!')
    elseif rs == ROUND_STATE_SURVIVORS_WIN then
        play_sound(SOUND_MENU_CLICK_CHANGE_VIEW, gMarioStates[0].marioObj.header.gfx.cameraToObject)
        djui_chat_message_create('The survivors have escaped!')
    end
end

function on_zombie_changed(tag, oldVal, newVal)
    local m = gMarioStates[tag]
    local np = gNetworkPlayers[tag]
    local lp = gPlayerSyncTable[gMarioStates[0].playerIndex]

    -- Show popup for remaining survivors
    if newVal and not oldVal then
        if not lp.zombie then
            play_sound(SOUND_OBJ_BOWSER_LAUGH, m.marioObj.header.gfx.cameraToObject)
            playerColor = network_get_player_text_color_string(m.playerIndex)
            djui_popup_create(playerColor .. np.name .. '\\#a0ffa0\\ has been infected', 2)
        end
    end

    if newVal then
        network_player_set_description(np, "Zombie", 64, 255, 64, 255)
    else
        network_player_set_description(np, "Survivor", 128, 128, 128, 255)
    end
end

--------------
-- Commands --
--------------

function on_infection_command(msg)
    if not network_is_server() then
        djui_chat_message_create('Only the host can change this setting!')
        return true
    end
    if msg == 'on' then
        djui_chat_message_create('Infection: Enabled')
        gGlobalSyncTable.infection = true
        return true
    elseif msg == 'off' then
        djui_chat_message_create('Infection: Disabled')
        gGlobalSyncTable.infection = false
        return true
    end
    return false
end

function on_punish_warping_command(msg)
    if not network_is_server() then
        djui_chat_message_create('Only the host can change this setting!')
        return true
    end
    if msg == 'on' then
        djui_chat_message_create('Punish Warping: Yes')
        gGlobalSyncTable.punish_warping = true
        return true
    elseif msg == 'off' then
        djui_chat_message_create('Punish Warping: No')
        gGlobalSyncTable.punish_warping = false
        return true
    end
    return false
end

-----------
-- Hooks --
-----------

hook_event(HOOK_UPDATE, update)
hook_event(HOOK_MARIO_UPDATE, mario_update)
hook_event(HOOK_BEFORE_PHYS_STEP, mario_before_phys_step)
hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)
hook_event(HOOK_ON_HUD_RENDER, on_hud_render)
hook_event(HOOK_ALLOW_PVP_ATTACK, allow_pvp_attack)
hook_event(HOOK_ON_PAUSE_EXIT, on_pause_exit)

hook_chat_command('infection', "[on|off] - Turn Infection on or off", on_infection_command)
hook_chat_command('punish-warping', "[on|off] - Whether or not to punish a survivor for pause-exiting", on_infection_command)

-- Call functions when certain sync table values change
hook_on_sync_table_change(gGlobalSyncTable, 'roundState', 0, on_round_state_changed)
for i = 0,(MAX_PLAYERS - 1) do
    gPlayerSyncTable[i].zombie = true
    hook_on_sync_table_change(gPlayerSyncTable[i], 'zombie', i, on_zombie_changed)
    network_player_set_description(gNetworkPlayers[i], "Zombie", 64, 255, 64, 255)
end
