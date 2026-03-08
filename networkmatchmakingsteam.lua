Global.matchmaking_lobbies = Global.matchmaking_lobbies or {}

local MAX_PEER_NAME_LENGTH = 32
local unknown_key = "[unknown key]"
local function sanitize_peer_name(name)
	if not name then
		return "[unknown]"
	end

	name = name:gsub("[%c]", "")
	name = utf8.sub(name, 1, MAX_PEER_NAME_LENGTH)

	return name
end

local function validated_value(lobby, key)
	local value = lobby:key_value(key)

	if value ~= "value_missing" and value ~= "value_pending" then
		return value
	end

	return nil
end

local function make_room_info(lobby)
	local lobby_version = Global.matchmaking_lobbies[lobby:id()]
	if not lobby_version then
		for version, key in pairs(tweak_data.matchmaking_keys) do
			if validated_value(lobby, key) then
				lobby_version = version
			end
		end

		Global.matchmaking_lobbies[lobby:id()] = lobby_version or unknown_key
	end

	local room_info = {
		owner_id = lobby:key_value("owner_id"),
		owner_name = lobby:key_value("owner_name"),
		owner_account_id = lobby:key_value("owner_id"),
		room_id = lobby:id(),
		owner_level = lobby:key_value("owner_level"),
		game_version = Global.matchmaking_lobbies[lobby:id()]
	}

	return room_info
end

function NetworkMatchMakingSTEAM:_lobby_to_numbers(lobby)
	return {
		(validated_value(lobby, "level") and validated_value(lobby, "job_id")) and tonumber(lobby:key_value("level")) + 1000 * tonumber(lobby:key_value("job_id")) or tonumber(1),
		tonumber(lobby:key_value("difficulty")),
		tonumber(lobby:key_value("permission")),
		tonumber(lobby:key_value("state")),
		tonumber(lobby:key_value("num_players")),
		tonumber(lobby:key_value("drop_in")),
		tonumber(lobby:key_value("min_level")),
		tonumber(lobby:key_value("kick_option")),
		tonumber(lobby:key_value("job_class")),
		tonumber(lobby:key_value("job_plan"))
	}
end

function NetworkMatchMakingSTEAM:search_lobby()
	local function refresh_lobby()
		if not self.browser then
			return
		end

		local lobbies = self.browser:lobbies()
		local info = {
			room_list = {},
			attribute_list = {}
		}

		if lobbies then
			for _, lobby in ipairs(lobbies) do
				local difficulty = tonumber(lobby:key_value("difficulty"))
				local room_info = make_room_info(lobby)
				local show_vanilla_servers = true
				if Global.game_settings.search_friends_only then
					show_vanilla_servers = room_info.game_version ~= "Vanilla"
				end

				room_info.owner_name = string.format("%s\n%s", room_info.game_version, sanitize_peer_name(room_info.owner_name))

				local filters_passed = validated_value(lobby, "owner_name") and utf8.len(lobby:key_value("owner_name")) <= MAX_PEER_NAME_LENGTH and (self._difficulty_filter == 0 or self._difficulty_filter == difficulty) and show_vanilla_servers
				if filters_passed then
					table.insert(info.room_list, room_info)

					local numbers = self:_lobby_to_numbers(lobby)
					if not validated_value(lobby, self._BUILD_SEARCH_INTEREST_KEY) then
						numbers[1] = 1
					end

					local attributes_data = {
						numbers = numbers,
						mutators = type(self._get_mutators_from_lobby) == "function" and self:_get_mutators_from_lobby(lobby),
						crime_spree = tonumber(validated_value(lobby, "crime_spree")),
						crime_spree_mission = validated_value(lobby, "crime_spree_mission"),
						mods = validated_value(lobby, "mods"),
						one_down = tonumber(validated_value(lobby, "one_down")),
						skirmish = tonumber(validated_value(lobby, "skirmish")),
						skirmish_wave = tonumber(validated_value(lobby, "skirmish_wave")),
						skirmish_weekly_modifiers = validated_value(lobby, "skirmish_weekly_modifiers")
					}

					table.insert(info.attribute_list, attributes_data)
				end
			end
		end

		self:_call_callback("search_lobby", info)
	end

	self.browser = LobbyBrowser(refresh_lobby, function() end)
	self.browser:set_interest_keys({})
	self.browser:set_distance_filter(3)
	self.browser:set_max_lobby_return_count(100)
	self.browser:refresh()
end