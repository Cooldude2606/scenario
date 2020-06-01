
local Event = require 'utils.event' ---@dep utils.event
local config = require 'config.statistics' ---@dep config.statistics
local floor = math.floor
local afk_required = 5*3600 -- 5 minutes

--- Stores the statistics on a player
local PlayerData = require 'expcore.player_data' --- @dep expcore.player_data
local AllPlayerData = PlayerData.All
local Statistics = PlayerData.Statistics
Statistics:set_metadata{
    display_order = config.display_order
}

--- Update your statistics with any which happened before the data was valid
Statistics:on_load(function(player_name, player_statistics)
    local existing_data = AllPlayerData:get(player_name)
    if existing_data and existing_data.valid then return end
    local counters = config.counters
    for key, value in pairs(Statistics:get(player_name, {})) do
        if config[key] or counters[key] then
            if not player_statistics[key] then
                player_statistics[key] = value
            else
                player_statistics[key] = player_statistics[key] + value
            end
        end
    end
    return player_statistics
end)

--- Add Playtime and AfkTime if it is enabled
if config.Playtime or config.AfkTime then
    local playtime, afk_time
    if config.Playtime then playtime = Statistics:combine('Playtime') end
    if config.AfkTime then afk_time = Statistics:combine('AfkTime') end
    Event.on_nth_tick(3600, function()
        if game.tick == 0 then return end
        for _, player in pairs(game.connected_players) do
            if playtime then playtime:increment(player) end
            if afk_time and player.afk_time > afk_required then afk_time:increment(player) end
        end
    end)
end

--- Add DistanceTraveled if it is enabled
if config.DistanceTraveled then
    local stat = Statistics:combine('DistanceTraveled')
    Event.add(defines.events.on_player_changed_position, function(event)
        local player = game.players[event.player_index]
        if not player.valid or not player.connected or player.afk_time > afk_required then return end
        stat:increment(player)
    end)
end

--- Add MachinesRemoved and TreesDestroyed and config.OreMined if it is enabled
if config.MachinesRemoved or config.TreesDestroyed or config.OreMined then
    local machines, trees, ore
    if config.MachinesRemoved then machines = Statistics:combine('MachinesRemoved') end
    if config.TreesDestroyed then trees = Statistics:combine('TreesDestroyed') end
    if config.OreMined then ore = Statistics:combine('OreMined') end
    local function on_event(event)
        if not event.player_index then return end  -- Check player is valid
        local player = game.players[event.player_index]
        if not player.valid or not player.connected then return end
        local entity = event.entity -- Check entity is valid
        if not entity.valid then return end
        if entity.type == 'resource' then ore:increment(player)
        elseif entity.type == 'tree' then trees:increment(player)
        elseif entity.force == player.force then machines:increment(player) end
    end
    Event.add(defines.events.on_marked_for_deconstruction, on_event)
    Event.add(defines.events.on_player_mined_entity, on_event)
end

--- Add DamageDealt if it is enabled
if config.DamageDealt then
    local stat = Statistics:combine('DamageDealt')
    Event.add(defines.events.on_entity_damaged, function(event)
        local character = event.cause -- Check character is valid
        if not character.valid or character.type ~= 'character' then return end
        local player = character.player -- Check player is valid
        if not player.valid or not player.connected then return end
        local entity = event.entity -- Check entity is valid
        if not entity.valid or entity.force == player.force or entity.force.name == 'neutral' then return end
        stat:increment(player, floor(event.final_damage_amount))
    end)
end

--- Add Kills if it is enabled
if config.Kills then
    local stat = Statistics:combine('Kills')
    Event.add(defines.events.on_entity_died, function(event)
        local character = event.cause -- Check character is valid
        if not character or not character.valid or character.type ~= 'character' then return end
        local player = character.player -- Check player is valid
        if not player.valid or not player.connected then return end
        local entity = event.entity -- Check entity is valid
        if not entity.valid or entity.force == player.force or entity.force.name == 'neutral' then return end
        stat:increment(player)
    end)
end

--- Add RocketsLaunched if it is enabled
if config.RocketsLaunched then
    local stat = Statistics:combine('RocketsLaunched')
    Event.add(defines.events.on_rocket_launched, function(event)
        local silo = event.rocket_silo -- Check silo is valid
        if not silo or not silo.valid then return end
        local force = silo.force -- Check force is valid
        if not force or not force.valid then return end
        for _, player in pairs(force.connected_players) do
            stat:increment(player)
        end
    end)
end

--- Add RocketsLaunched if it is enabled
if config.ResearchCompleted then
    local stat = Statistics:combine('ResearchCompleted')
    Event.add(defines.events.on_research_finished, function(event)
        local research  = event.research  -- Check research  is valid
        if event.by_script or not research or not research.valid then return end
        local force = research.force -- Check force is valid
        if not force or not force.valid then return end
        for _, player in pairs(force.connected_players) do
            stat:increment(player)
        end
    end)
end

--- Add all the remaining statistics from the config
for statistic, event_name in pairs(config.counters) do
    local stat = Statistics:combine(statistic)
    Event.add(event_name, function(event)
        if not event.player_index then return end
        local player = game.players[event.player_index]
        if not player.valid or not player.connected then return end
        stat:increment(player)
    end)
end