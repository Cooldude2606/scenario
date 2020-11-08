--[[-- Gui Module - Warp List
    - Adds a warp list gui which allows players to add and remove warp points
    @gui Warps-List
    @alias warp_list
]]

local Gui = require 'expcore.gui' --- @dep expcore.gui
local Datastore = require 'expcore.datastore' --- @dep expcore.datastore
local Global = require 'utils.global' --- @dep utils.global
local Event = require 'utils.event' --- @dep utils.event
local Roles = require 'expcore.roles' --- @dep expcore.roles
local Colors = require 'utils.color_presets' --- @dep utils.color_presets
local config = require 'config.gui.warps' --- @dep config.gui.warps
local Warps = require 'modules.control.warps' --- @dep modules.control.warps
local format_time = _C.format_time --- @dep expcore.common

--- Stores all data for the warp gui
local WrapGuiData = Datastore.connect('WrapGuiData')
WrapGuiData:set_serializer(Datastore.name_serializer)
local PlayerInRange = WrapGuiData:combine('PlayerInRange')
PlayerInRange:set_default(false)
local PlayerCooldown = WrapGuiData:combine('PlayerCooldown')
PlayerCooldown:set_default(0)

--- Table that stores a boolean value of weather to keep the warp gui open
local keep_gui_open = {}
Global.register(keep_gui_open, function(tbl)
    keep_gui_open = tbl
end)

--- Styles used for sprite buttons
local Styles = {
    sprite22 = { height = 22, width = 22, padding = -2 },
    sprite32 = { height = 32, width = 32, left_margin = 1 }
}

--- Returns if a player is allowed to edit the given warp
--- If a player is allowed to use the edit buttons
local function check_player_permissions(player, action, warp)
    -- Check if the action is allow edit and then check bypass settings
    if action == 'allow_edit_warp' then
        -- Check if the warp is the spawn then it cant be edited
        local spawn_id = Warps.get_spawn_warp_id(player.force.name)
        if spawn_id == warp.warp_id then
            return false
        end

        -- Check if the player being the last to edit will override existing permisisons
        if config.user_can_edit_own_warps and warp.last_edit_name == player.name then
            return true
        end
    end

    -- Check player has permission based on value in the config
    local action_config = config[action]
    if action_config == 'all' then
        return true
    elseif action_config == 'admin' then
        return player.admin
    elseif action_config == 'expcore.roles' then
        return Roles.player_allowed(player, config['expcore_roles_'..action])
    end

    -- Return false as all other conditions have not been met
    return false
end

--- Will add a new warp to the list, checks if the player is too close to an existing one
-- @element add_new_warp
local add_new_warp =
Gui.element{
    type = 'sprite-button',
    sprite = 'utility/add',
    tooltip = {'warp-list.add-tooltip'},
    style = 'shortcut_bar_button'
}
:style(Styles.sprite22)
:on_click(function(player, _)
    -- Add the new warp
    local force_name = player.force.name
    local surface = player.surface
    local position = player.position
    local warp_id = Warps.add_warp(force_name, surface, position, player.name)
    Warps.make_warp_tag(warp_id)
    Warps.make_warp_area(warp_id)
end)


--- Warp icon button, this will trigger a warp when the player is able to
-- @element warp_icon_button
local warp_icon_button =
Gui.element(function(event_trigger, parent, warp)
    local warp_position = warp.position

    -- The SpritePath type is not the same as the SignalID type
    local sprite = warp.icon.type .. '/' ..warp.icon.name
    if warp.icon.type == 'virtual' then
        sprite = 'virtual-signal/' ..warp.icon.name
    end

    -- Draw the element
    return parent.add{
        name = event_trigger,
        type = 'sprite-button',
        sprite = sprite,
        tooltip = {'warp-list.goto-tooltip', warp_position.x, warp_position.y},
        style = 'slot_button'
    }
end)
:style(Styles.sprite32)
:on_click(function(player, element, _)
    if element.type == 'choose-elem-button' then return end
    local warp_id = element.parent.caption
    Warps.teleport_player(warp_id, player)

    -- Reset the warp cooldown if the player does not have unlimited warps
    if not check_player_permissions(player, 'bypass_warp_cooldown') then
        PlayerCooldown:set(player, config.cooldown_duration)
    end

    PlayerInRange:set(player, warp_id)
end)

--- The button that is visible when the warp is in edit state
-- @element warp_icon_editing
local warp_icon_editing =
Gui.element(function(event_trigger, parent, warp)
    return parent.add{
        name = event_trigger,
        type = 'choose-elem-button',
        elem_type = 'signal',
        signal = {type = warp.icon.type, name = warp.icon.name},
        tooltip = {'warp-list.goto-edit'}
    }
end)
:style(Styles.sprite32)

--- Warp label, visible if the player is not in edit state
-- @element warp_label
local warp_label =
Gui.element(function(event_trigger, parent, warp)
    local last_edit_name = warp.last_edit_name
    local last_edit_time = warp.last_edit_time
    -- Draw the element
    return parent.add{
        name = event_trigger,
        type = 'label',
        caption = warp.name,
        tooltip = {'warp-list.last-edit', last_edit_name, format_time(last_edit_time)}
    }
end)
:style{
    single_line = false,
    horizontally_stretchable = true
}
:on_click(function(player, element, _)
    local warp_id = element.parent.caption
    local warp = Warps.get_warp(warp_id)
    local position = warp.position
    player.zoom_to_world(position, 1.5)
end)

--- Warp textfield, visible if the player is in edit state
-- @element warp_textfield
local warp_textfield =
Gui.element(function(event_trigger, parent, warp)
    -- Draw the element
    local element =
    parent.add{
        name = event_trigger,
        type = 'textfield',
        text = warp.name,
        clear_and_focus_on_right_click = true
    }

    -- Return the element
    return element
end)
:style{
    maximal_width = 81,
    height = 22,
    padding = -2
}
:on_confirmed(function(player, element, _)
    local warp_id = element.parent.caption
    local warp_name = element.text
    local warp_icon = element.parent.parent['icon-'..warp_id][warp_icon_editing.name].elem_value
    Warps.set_editing(warp_id, player.name)
    Warps.update_warp(warp_id, warp_name, warp_icon, player.name)
end)


--- Confirms the edit to name or icon of the warp
-- @element confirm_edit_button
local confirm_edit_button =
Gui.element{
    type = 'sprite-button',
    sprite = 'utility/confirm_slot',
    tooltip = {'warp-list.confirm-tooltip'},
    style = 'shortcut_bar_button_green'
}
:style(Styles.sprite22)
:on_click(function(player, element)
    local warp_id = element.parent.caption
    local warp_name = element.parent.parent['name-'..warp_id][warp_textfield.name].text
    local warp_icon = element.parent.parent['icon-'..warp_id][warp_icon_editing.name].elem_value
    Warps.set_editing(warp_id, player.name)
    Warps.update_warp(warp_id, warp_name, warp_icon, player.name)
end)

--- Cancels the editing changes of the selected warp name or icon
-- @element cancel_edit_button
local cancel_edit_button =
Gui.element{
    type = 'sprite-button',
    sprite = 'utility/close_black',
    tooltip = {'warp-list.cancel-tooltip'},
    style = 'shortcut_bar_button_red'
}
:style(Styles.sprite22)
:on_click(function(player, element)
    local warp_id = element.parent.caption
    Warps.set_editing(warp_id, player.name)
end)

--- Removes a warp from the list, including the physical area and map tag
-- @element remove_warp_button
local remove_warp_button =
Gui.element{
    type = 'sprite-button',
    sprite = 'utility/trash',
    tooltip = {'warp-list.discard-tooltip'},
    style = 'shortcut_bar_button_red'
}
:style(Styles.sprite22)
:on_click(function(_, element)
    local warp_id = element.parent.caption
    Warps.remove_warp(warp_id)
end)

--- Opens edit mode for the warp
-- @element edit_warp_button
local edit_warp_button =
Gui.element{
    type = 'sprite-button',
    sprite = 'utility/rename_icon_normal',
    tooltip = {'warp-list.edit-tooltip-none'},
    style = 'shortcut_bar_button'
}
:style(Styles.sprite22)
:on_click(function(player, element)
    local warp_id = element.parent.caption
    Warps.set_editing(warp_id, player.name, true)
end)

local update_wrap_buttons
--- Set of three elements which make up each row of the warp table
-- @element add_warp_elements
local add_warp_elements =
Gui.element(function(_, parent, warp)
    -- Add icon flow this will contain the warp button and warp icon edit button
    local icon_flow = parent.add{
        name = 'icon-'..warp.warp_id,
        type = 'flow',
        caption = warp.warp_id
    }
    icon_flow.style.padding = 0

    -- Add the button and the icon edit button
    warp_icon_button(icon_flow, warp)
    warp_icon_editing(icon_flow, warp)

    -- Add name flow this will contain the warp label and textbox
    local name_flow = parent.add{
        type = 'flow',
        name = 'name-'..warp.warp_id,
        caption = warp.warp_id
    }
    name_flow.style.padding = 0

    -- Add the label and textfield of the warp
    warp_label(name_flow, warp)
    warp_textfield(name_flow, warp)


    -- Add button flow this will contain buttons to manage this specific warp
    local button_flow = parent.add{
        type = 'flow',
        name = 'button-'..warp.warp_id,
        caption = warp.warp_id
    }
    button_flow.style.padding = 0

    -- Add both edit state buttons
    confirm_edit_button(button_flow)
    cancel_edit_button(button_flow)
    edit_warp_button(button_flow)
    remove_warp_button(button_flow)

    -- Return the warp flow elements
    return { icon_flow, name_flow, button_flow }
end)

-- Removes the three elements that are added as part of the warp base
local function remove_warp_elements(parent, warp_id)
    Gui.destroy_if_valid(parent['icon-'..warp_id])
    Gui.destroy_if_valid(parent['name-'..warp_id])
    Gui.destroy_if_valid(parent['button-'..warp_id])
end

--- This timer controls when a player is able to warp, eg every 60 seconds
-- @element warp_timer
local warp_timer =
Gui.element{
    type = 'progressbar',
    tooltip = {'warp-list.timer-tooltip', config.cooldown_duration},
    minimum_value = 0,
    maximum_value = config.cooldown_duration*config.update_smoothing
}
:style{
    horizontally_stretchable = true,
    color = Colors.light_blue
}

local warp_list_container

-- Helper function to style and enable or disable a button element
local function update_icon_button(element, on_cooldown, warp, warp_player_is_on)
    -- Check if button element is valid
    if not element or not element.valid then return end

    local label_style = element.parent.parent['name-'..warp.warp_id][warp_label.name].style

    if not warp_player_is_on then
        element.tooltip = {'warp-list.goto-disabled'}
        element.enabled = false
        label_style.font_color = { 1, 1, 1, 0.7 }
        return
    end

    if warp_player_is_on.warp_id == warp.warp_id then
        element.tooltip = {'warp-list.goto-same-warp'}
        element.enabled = false
        label_style.font_color = { 1, 1, 1, 0.7 }
    elseif on_cooldown then
        element.tooltip = {'warp-list.goto-cooldown'}
        element.enabled = false
        label_style.font_color = { 1, 1, 1, 0.7 }
    else
        -- Check if the warps are in the same electricity network
        local warp_electric_network_id = warp.electric_pole and warp.electric_pole.electric_network_id or -1
        local player_warp_electric_network_id = warp_player_is_on.electric_pole and warp_player_is_on.electric_pole.electric_network_id or -2
        if warp_electric_network_id == player_warp_electric_network_id then
            local position = warp_player_is_on.position
            element.tooltip = {'warp-list.goto-tooltip', position.x, position.y}
            element.enabled = true
            label_style.font_color = { 1, 1, 1, 1 }
        else
            element.tooltip = {'warp-list.goto-different-network'}
            element.enabled = false
            label_style.font_color = { 1, 0, 0, 0.7 }
        end
    end
end

--- Update the warp buttons for a player
function update_wrap_buttons(player, timer, warp_id)
    -- Get the warp table
    local frame = Gui.get_left_element(player, warp_list_container)
    local scroll_table = frame.container.scroll.table

    -- Check if the buttons should be active
    timer = timer or PlayerCooldown:get(player)
    warp_id = warp_id or PlayerInRange:get(player)
    local on_cooldown = timer > 0

    local warp_player_is_on = warp_id and Warps.get_warp(warp_id) or nil

    -- Change the enabled state of the warp buttons
    local warp_ids = Warps.get_force_warp_ids(player.force.name)
    for _, next_warp_id in pairs(warp_ids) do
        local element = scroll_table['icon-'..next_warp_id][warp_icon_button.name]
        local next_warp = Warps.get_warp(next_warp_id)
        update_icon_button(element, on_cooldown, next_warp, warp_player_is_on)
    end
end

--- Updates a warp for a player
local function update_warp(player, warp_table, warp_id)
    local warp = Warps.get_warp(warp_id)

    -- If the warp does no longer exist then remove the warp elements from the warp table
    if not warp then
        remove_warp_elements(warp_table, warp_id)
        return
    end

    -- Check if the warp elements are created, if they are not then create a new set of them
    if not warp_table['icon-'..warp_id] then
        add_warp_elements(warp_table, warp)
    end
    local icon_flow = warp_table['icon-'..warp_id]
    local name_flow = warp_table['name-'..warp_id]
    local button_flow = warp_table['button-'..warp_id]

    -- Create local references to the elements for this warp
    local warp_icon_element = icon_flow[warp_icon_button.name]
    local warp_icon_edit_element = icon_flow[warp_icon_editing.name]

    local label_element = name_flow[warp_label.name]
    local textfield_element = name_flow[warp_textfield.name]

    local cancel_edit_element = button_flow[cancel_edit_button.name]
    local confirm_edit_element = button_flow[confirm_edit_button.name]

    local edit_warp_element = button_flow[edit_warp_button.name]
    local remove_warp_element = button_flow[remove_warp_button.name]

    -- Hide the edit button if the player is not allowed to edit the warp
    local player_allowed_edit = check_player_permissions(player, 'allow_edit_warp', warp)
    local players_editing = table.get_keys(warp.currently_editing)
    -- button_flow.visible = player_allowed_edit
    edit_warp_element.visible = player_allowed_edit
    remove_warp_element.visible = player_allowed_edit

    -- Set the tooltip of the edit button
    if #players_editing > 0 then
        edit_warp_element.hovered_sprite = 'utility/warning_icon'
        edit_warp_element.tooltip = {'warp-list.edit-tooltip', table.concat(players_editing, ', ')}
    else
        edit_warp_element.hovered_sprite = edit_warp_element.sprite
        edit_warp_element.tooltip = {'warp-list.edit-tooltip-none'}
    end

    -- Set the warp elements visibility based on if the user is editing or not
    local player_is_editing = warp.currently_editing[player.name]
    if player_is_editing then
        -- Set the icon elements visibility
        warp_icon_element.visible = false
        warp_icon_edit_element.visible = true
        -- Set the name elements visibility
        label_element.visible = false
        textfield_element.visible = true
        textfield_element.focus()
        warp_table.parent.scroll_to_element(textfield_element, 'top-third')
        -- Set the edit buttons
        cancel_edit_element.visible = true
        confirm_edit_element.visible = true
        -- Set the warp buttons
        edit_warp_element.visible = false
        remove_warp_element.visible = false
    else
        -- Set the icon elements visibility
        warp_icon_element.visible = true
        warp_icon_edit_element.visible = false
        -- Set the name elements visibility
        label_element.visible = true
        textfield_element.visible = false
        -- Set the edit buttons
        cancel_edit_element.visible = false
        confirm_edit_element.visible = false
        -- Set the warp buttons
        edit_warp_element.visible = true and player_allowed_edit
        remove_warp_element.visible = true and player_allowed_edit
    end

    local timer = PlayerCooldown:get(player)
    local current_warp_id = PlayerInRange:get(player)
    local to_warp = current_warp_id and Warps.get_warp(current_warp_id) or nil
    local apply_proximity = not check_player_permissions(player, 'bypass_warp_proximity')
    update_icon_button(warp_icon_element, timer > 0 or (apply_proximity and not current_warp_id), warp, to_warp)
end

-- Update all the warps for a player
local function update_all_warps(player, warp_table)
    local warp_ids = Warps.get_force_warp_ids(player.force.name)
    warp_table.clear()
    for _, warp_id in ipairs(warp_ids) do
        update_warp(player, warp_table, warp_id)
    end
end

-- Update all warps for all players on a force
local function update_all_warp_force(force)
    local warp_ids = Warps.get_force_warp_ids(force.name)
    for _, player in pairs(force.connected_players) do
        local frame = Gui.get_left_element(player, warp_list_container)
        local warp_table = frame.container.scroll.table

        warp_table.clear()
        for _, warp_id in ipairs(warp_ids) do
            update_warp(player, warp_table, warp_id)
        end
    end
end

--- Main warp list container for the left flow
-- @element warp_list_container
warp_list_container =
Gui.element(function(event_trigger, parent)
    -- Draw the internal container
    local container = Gui.container(parent, event_trigger, 200)

    -- Draw the header
    local header = Gui.header(
        container,
        {'warp-list.main-caption'},
        {'warp-list.sub-tooltip', config.cooldown_duration, config.standard_proximity_radius},
        true
    )

    -- Draw the new warp button
    local player = Gui.get_player_from_element(parent)
    local add_new_warp_element = add_new_warp(header)
    add_new_warp_element.visible = check_player_permissions(player, 'allow_add_warp')

    -- Draw the scroll table for the warps
    local scroll_table = Gui.scroll_table(container, 250, 3)
    -- Set the scroll panel to always show the scrollbar (not doing this will result in a changing gui size)
    scroll_table.parent.vertical_scroll_policy = 'always'

    -- Change the style of the scroll table
    local scroll_table_style = scroll_table.style
    scroll_table_style.top_cell_padding = 3
    scroll_table_style.bottom_cell_padding = 3

    -- Draw the warp cooldown progress bar
    local warp_timer_element = warp_timer(container)

    -- Change the progress of the warp timer
    local progress = 1
    local timer = PlayerCooldown:get(player)
    if timer > 0 then
        progress = 1 - (timer/config.cooldown_duration)
    end
    warp_timer_element.value = progress

    -- Add any existing warps
    update_all_warps(player, scroll_table)

    -- Return the external container
    return container.parent
end)
:add_to_left_flow()

--- Button on the top flow used to toggle the warp list container
-- @element warp_list_toggle
Gui.left_toolbar_button(config.default_icon.type ..'/'..config.default_icon.name, {'warp-list.main-tooltip', config.standard_proximity_radius}, warp_list_container, function(player)
    return Roles.player_allowed(player, 'gui/warp-list')
end)
:on_custom_event(Gui.events.on_visibility_changed_by_click, function(player, _,event)
    -- Set gui keep open state for player that clicked the button: true if visible, false if invisible
    keep_gui_open[player.name] = event.state
end)

--- When the name of a warp is updated this is triggered
Warps.on_update(function(_, warp, old_warp)
    -- Get the force to update, warp is nil when removed
    if warp then
        update_all_warp_force(game.forces[warp.force_name])
    else
        update_all_warp_force(game.forces[old_warp.force_name])
    end
end)

--- When the player leaves or enters range of a warp this is triggered
PlayerInRange:on_update(function(player_name, warp_id)
    local player = game.players[player_name]

    -- Change if the frame is visible based on if the player is in range
    if not keep_gui_open[player.name] then
        Gui.toggle_left_element(player, warp_list_container, warp_id ~= nil)
    end

    -- Check if the player requires proximity
    if not check_player_permissions(player, 'bypass_warp_proximity') then
        update_wrap_buttons(player, nil, warp_id)
    end
end)

--- Update the warp cooldown progress bars to match the current cooldown
PlayerCooldown:on_update(function(player_name, player_cooldown)
    -- Get the progress bar element
    local player = game.players[player_name]
    local frame = Gui.get_left_element(player, warp_list_container)
    local warp_timer_element = frame.container[warp_timer.name]

    -- Set the progress
    local progress = 1
    if player_cooldown and player_cooldown > 0 then
        progress = 1 - (player_cooldown/config.cooldown_duration)
    end
    warp_timer_element.value = progress

    -- Trigger update of buttons if cooldown is now 0
    if player_cooldown == 0 then
        update_wrap_buttons(player, player_cooldown, nil)
    end
end)

--- Handles updating the timer and checking distance from a warp
local r2 = config.standard_proximity_radius^2
local rs2 = config.spawn_proximity_radius^2
local mr2 = config.minimum_distance^2
Event.on_nth_tick(math.floor(60/config.update_smoothing), function()
    PlayerCooldown:update_all(function(_, player_cooldown)
        if player_cooldown > 0 then return player_cooldown - 1 end
    end)

    local force_warps = {}
    local warps = {}
    for _, player in pairs(game.connected_players) do
        local was_in_range = PlayerInRange:get(player)

        -- Get the ids of all the warps on the players force
        local force_name = player.force.name
        local warp_ids = force_warps[force_name]
        if not warp_ids then
            warp_ids = Warps.get_force_warp_ids(force_name)
            force_warps[force_name] = warp_ids
        end

        -- Check if the force has any warps
        local closest_warp
        local closest_distance
        if #warp_ids > 0 then
            local surface = player.surface
            local pos = player.position
            local px, py = pos.x, pos.y

            -- Loop over each warp
            for _, warp_id in ipairs(warp_ids) do
                -- Check if warp id is cached
                local warp = warps[warp_id]
                if not warp then
                    warp = Warps.get_warp(warp_id)
                    warps[warp_id] = warp
                end

                -- Check if the player is within range
                local warp_pos = warp.position
                if warp.surface == surface then
                    local dx, dy = px-warp_pos.x, py-warp_pos.y
                    local dist = (dx*dx)+(dy*dy)
                    if closest_distance == nil or dist < closest_distance then
                        closest_warp = warp
                        closest_distance = dist
                        if dist < r2 then break end
                    end
                end
            end

            -- Check the dist to the closest warp
            local in_range = closest_warp.warp_id == warp_ids.spawn and closest_distance < rs2 or closest_distance < r2
            if was_in_range and not in_range then
                PlayerInRange:set(player, nil)
            elseif not was_in_range and in_range then
                PlayerInRange:set(player, closest_warp.warp_id)
            end

            -- Change the enabled state of the add warp button
            local frame = Gui.get_left_element(player, warp_list_container)
            local add_warp_element = frame.container.header.alignment[add_new_warp.name]
            local old_closest_warp_name = add_warp_element.tooltip[2] or closest_warp.name
            local was_able_to_make_warp = add_warp_element.enabled
            local can_make_warp = closest_distance > mr2
            if can_make_warp and not was_able_to_make_warp then
                add_warp_element.enabled = true
                add_warp_element.tooltip = {'warp-list.add-tooltip'}
            elseif not can_make_warp and was_able_to_make_warp or old_closest_warp_name ~= closest_warp.name then
                add_warp_element.enabled = false
                add_warp_element.tooltip = {'warp-list.too-close', closest_warp.name}
            end

        end

    end

end)

--- When a player is created make sure that there is a spawn warp created
Event.add(defines.events.on_player_created, function(event)
    -- If the force has no spawn then make a spawn warp
    local player = game.players[event.player_index]
    local force = player.force
    local spawn_id = Warps.get_spawn_warp_id(force.name)
    if not spawn_id then
        local spawn_position = force.get_spawn_position(player.surface)
        spawn_id = Warps.add_warp(force.name, player.surface, spawn_position, nil, 'Spawn')
        Warps.set_spawn_warp(spawn_id, force)
        Warps.make_warp_tag(spawn_id)

        local entities = player.surface.find_entities_filtered{ type = 'electric-pole', position = spawn_position, radius = 20, limit = 1 }
        if entities and entities[1] then
            local warp = Warps.get_warp(spawn_id)
            warp.electric_pole = entities[1]
        end
    end
end)

--- Update the warps when the player joins
Event.add(defines.events.on_player_joined_game, function(event)
    local player = game.players[event.player_index]
    local frame = Gui.get_left_element(player, warp_list_container)
    local scroll_table = frame.container.scroll.table
    update_all_warps(player, scroll_table)
end)

--- Makes sure the right buttons are present when roles change
local function role_update_event(event)
    local player = game.players[event.player_index]
    local container = Gui.get_left_element(player, warp_list_container).container

    -- Update the warps, incase the user can now edit them
    local scroll_table = container.scroll.table
    update_all_warps(player, scroll_table)

    -- Update the new warp button incase the user can now add them
    local add_new_warp_element = container.header.alignment[add_new_warp.name]
    add_new_warp_element.visible = check_player_permissions(player, 'allow_add_warp')
end

Event.add(Roles.events.on_role_assigned, role_update_event)
Event.add(Roles.events.on_role_unassigned, role_update_event)

--- When a chart tag is removed or edited make sure it is not one that belongs to a warp
local function maintain_tag(event)
    if not event.player_index then return end
    local tag = event.tag
    local force_name = event.force.name
    local warp_ids = Warps.get_force_warp_ids(force_name)
    for _, warp_id in pairs(warp_ids) do
        local warp = Warps.get_warp(warp_id)
        local warp_tag = warp.tag
        if not warp_tag or not warp_tag.valid or warp_tag == tag then
            if event.name == defines.events.on_chart_tag_removed then
                warp.tag = nil
            end
            Warps.make_warp_tag(warp_id)
        end
    end
end

Event.add(defines.events.on_chart_tag_modified, maintain_tag)
Event.add(defines.events.on_chart_tag_removed, maintain_tag)