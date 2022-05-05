-- name: Machinima
-- incompatible: 
-- description: A simple machinima mod. Type /help for a list of compatible commands.\n\nMade by sm64rise | version 1

-- Hides the HUD by default
hud_hide()

function on_freeze_command(msg)
    if msg == 'on' then
        camera_freeze()
        return true
    elseif msg == 'off' then
        camera_unfreeze()
        return true
    end
    return false
end

function on_hud_command(msg)
    if msg == 'hide' then
        hud_hide()
        return true
    elseif msg == 'show' then
        hud_show()
        return true
    end
    return false
end

-----------
-- hooks --
-----------

hook_chat_command('freeze', "[on|off] Freezes/unfreezes the camera", on_freeze_command)
hook_chat_command('hud', "[hide|show] Hides/unhides the HUD", on_hud_command)