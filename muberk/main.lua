-- name: Muberk
-- incompatible:
-- description: It's all Muberk? Always has been.\n\nMade by sm64rise | version 1

MODEL_MUBERK = smlua_model_util_get_id("muberk_geo")

function update_model(name, id)
    gPlayerSyncTable[id].modelId = MODEL_MUBERK
end

-- Hooks

function on_model_command(msg)
    if not network_is_server() then
        djui_chat_message_create('Only the host can use this command!')
        return true
    end
    update_model(msg, 0)
    return true
end

function on_player_connected(m)
    update_model(gNetworkPlayers[m.playerIndex].name, m.playerIndex)
end

function mario_update_local(m)
    if (m.controller.buttonPressed & D_JPAD) ~= 0 then
        update_model(gNetworkPlayers[m.playerIndex].name, m.playerIndex)
    end
end

function mario_update(m)
    if m.playerIndex == 0 then
        mario_update_local(m)
    end

    if gPlayerSyncTable[m.playerIndex].modelId ~= nil then
        obj_set_model_extended(m.marioObj, gPlayerSyncTable[m.playerIndex].modelId)
    end
end

hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)
hook_event(HOOK_MARIO_UPDATE, mario_update)