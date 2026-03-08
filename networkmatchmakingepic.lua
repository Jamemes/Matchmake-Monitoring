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
	if Global.game_settings.search_friends_only then
		local lobby_version = Global.matchmaking_lobbies[lobby:id()]
		if not lobby_version then
			for version, key in pairs(tweak_data.matchmaking_keys) do
				if validated_value(lobby, key) then
					lobby_version = version
				end
			end

			Global.matchmaking_lobbies[lobby:id()] = lobby_version or unknown_key
		end
	end

	local room_info = {
		owner_id = lobby:key_value("owner_id"),
		owner_name = lobby:key_value("owner_name"),
		owner_account_id = lobby:key_value("owner_id"),
		room_id = lobby:id(),
		owner_level = lobby:key_value("owner_level"),
		game_version = Global.matchmaking_lobbies[lobby:id()] or "Vanilla"
	}

	return room_info
end

function NetworkMatchMakingEPIC:_lobby_to_numbers(lobby)
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

function NetworkMatchMakingEPIC:search_lobby(friends_only, no_filters)
	if not self:_has_callback("search_lobby") then
		return
	end

	local function refresh_lobby()
		local lobbies = LobbyBrowser:lobbies()
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

				if room_info.game_version ~= "Vanilla" then
					room_info.owner_name = string.format("%s\n%s", room_info.game_version, sanitize_peer_name(room_info.owner_name))
				end

				local filters_passed = validated_value(lobby, "owner_name") and utf8.len(lobby:key_value("owner_name")) <= MAX_PEER_NAME_LENGTH and (self._difficulty_filter == 0 or self._difficulty_filter == difficulty) and show_vanilla_servers
				local numbers = self:_lobby_to_numbers(lobby)
				if not validated_value(lobby, self._BUILD_SEARCH_INTEREST_KEY) then
					if room_info.game_version ~= unknown_key then
						numbers[1] = 1
					end
				end
				if filters_passed then
					table.insert(info.room_list, room_info)
					local show_mutators = self._BUILD_SEARCH_INTEREST_KEY == tostring(tweak_data.matchmaking_keys[room_info.game_version])
					local attributes_data = {
						numbers = numbers,
						mutators = show_mutators and self:_get_mutators_from_lobby(lobby),
						crime_spree = tonumber(lobby:key_value("crime_spree")),
						crime_spree_mission = lobby:key_value("crime_spree_mission"),
						mods = lobby:key_value("mods"),
						one_down = tonumber(lobby:key_value("one_down")),
						skirmish = tonumber(lobby:key_value("skirmish")),
						skirmish_wave = tonumber(lobby:key_value("skirmish_wave")),
						skirmish_weekly_modifiers = lobby:key_value("skirmish_weekly_modifiers")
					}

					table.insert(info.attribute_list, attributes_data)
				end
			end
		end

		self:_call_callback("search_lobby", info)
	end

	LobbyBrowser:set_callbacks(refresh_lobby)
	LobbyBrowser:clear_lobby_filters()

	if not Global.game_settings.search_friends_only then
		local use_filters = not no_filters
		if Global.game_settings.gamemode_filter ~= GamemodeStandard.id then
			use_filters = false
		end

		LobbyBrowser:set_lobby_filter(self._BUILD_SEARCH_INTEREST_KEY, "true", "equal")

		local has_filter, filter_value, filter_type = self:get_modded_lobby_filter()

		if has_filter then
			LobbyBrowser:set_lobby_filter("mods", filter_value, filter_type)
		else
			LobbyBrowser:set_lobby_filter("mods")
		end

		local has_filter, filter_value, filter_type = self:get_allow_mods_filter()

		if has_filter then
			LobbyBrowser:set_lobby_filter("allow_mods", filter_value, filter_type)
		else
			LobbyBrowser:set_lobby_filter("allow_mods")
		end

		LobbyBrowser:set_lobby_filter("one_down", Global.game_settings.search_one_down_lobbies and 1 or 0, "equalto_less_than")

		if use_filters then
			LobbyBrowser:set_lobby_filter("min_level", managers.experience:current_level(), "equalto_less_than")

			if Global.game_settings.search_appropriate_jobs then
				local min_ply_jc = managers.job:get_min_jc_for_player()
				local max_ply_jc = managers.job:get_max_jc_for_player()

				LobbyBrowser:set_lobby_filter("job_class_min", min_ply_jc, "equalto_or_greater_than")
				LobbyBrowser:set_lobby_filter("job_class_max", max_ply_jc, "equalto_less_than")
			end
		end

		if not no_filters then
			if false then
				-- Nothing
			elseif Global.game_settings.gamemode_filter == GamemodeCrimeSpree.id then
				local min_level = 0

				if Global.game_settings.crime_spree_max_lobby_diff >= 0 then
					min_level = managers.crime_spree:spree_level() - (Global.game_settings.crime_spree_max_lobby_diff or 0)
					min_level = math.max(min_level, 0)
				end

				LobbyBrowser:set_lobby_filter("crime_spree", min_level, "equalto_or_greater_than")
				LobbyBrowser:set_lobby_filter("skirmish", 0, "equalto_less_than")
				LobbyBrowser:set_lobby_filter("skirmish_wave")
			elseif Global.game_settings.gamemode_filter == "skirmish" then
				local min = SkirmishManager.LOBBY_NORMAL

				LobbyBrowser:set_lobby_filter("crime_spree", -1, "equalto_less_than")
				LobbyBrowser:set_lobby_filter("skirmish", min, "equalto_or_greater_than")
				LobbyBrowser:set_lobby_filter("skirmish_wave", Global.game_settings.skirmish_wave_filter or 99, "equalto_less_than")
			elseif Global.game_settings.gamemode_filter == GamemodeStandard.id then
				LobbyBrowser:set_lobby_filter("crime_spree", -1, "equalto_less_than")
				LobbyBrowser:set_lobby_filter("skirmish", 0, "equalto_less_than")
				LobbyBrowser:set_lobby_filter("skirmish_wave")
			end
		end

		if use_filters then
			for key, data in pairs(self._lobby_filters) do
				if data.value and data.value ~= -1 then
					LobbyBrowser:set_lobby_filter(data.key, data.value, data.comparision_type)
					print(data.key, data.value, data.comparision_type)
				elseif LobbyBrowser.remove_lobby_filter then
					LobbyBrowser:remove_lobby_filter(data.key)
				end
			end
		end
	end

	LobbyBrowser:set_interest_keys({})
	LobbyBrowser:set_distance_filter(3)

	LobbyBrowser:set_max_lobby_return_count(190)
	LobbyBrowser:refresh()
end