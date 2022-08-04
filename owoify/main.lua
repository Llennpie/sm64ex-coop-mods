-- name: Project OwOify
-- description: sm64ex's "Project OwOify" mod, ported to sm64ex-coop.\n\nOriginal mod created by K1LLRxK1TT3H, chloerawr, Napstio, sm64rise, and KawaiiTemDev\n\nPorted to sm64ex-coop by sm64rise | version 2.0

MODEL_MAWIO = smlua_model_util_get_id("mawio_geo")
MODEL_MARIO = smlua_model_util_get_id("mario_geo")

-- Functions

function toggle_replace_mawio(m)
    if gPlayerSyncTable[m.playerIndex].modelId == nil then
        gPlayerSyncTable[m.playerIndex].modelId = MODEL_MAWIO
    else
        gPlayerSyncTable[m.playerIndex].modelId = nil
    end
end

-- Hooks

function on_player_connected(m)
    -- Mawio is enabled by default
    if m.character.type == CT_MARIO then
        gPlayerSyncTable[m.playerIndex].modelId = MODEL_MAWIO
    end
end

function mario_update_local(m)
    if gMarioStates[0].character.type ~= CT_MARIO then
		gPlayerSyncTable[0].modelId = nil
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

function run_mawio_command(msg)
    if get_character(gMarioStates[0]).type == CT_MARIO then
        toggle_replace_mawio(gMarioStates[0])
        return true
    else
        djui_chat_message_create('You must be Mario to run this command!')
        return true
    end
    return false
end

hook_chat_command('mawio', "- Toggles Mawio, only works with the Mario character", run_mawio_command)
hook_event(HOOK_MARIO_UPDATE, mario_update)
hook_event(HOOK_ON_PLAYER_CONNECTED, on_player_connected)